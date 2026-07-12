#include <stdint.h>

#define UART_BASE       0x40004000u

#define UART_CSR        (*(volatile uint32_t *)(UART_BASE + 0x00u))
#define UART_DIV        (*(volatile uint32_t *)(UART_BASE + 0x04u))
#define UART_FSTAT      (*(volatile uint32_t *)(UART_BASE + 0x08u))
#define UART_TX         (*(volatile uint32_t *)(UART_BASE + 0x0cu))
#define UART_RX         (*(volatile uint32_t *)(UART_BASE + 0x10u))

#define UART_CSR_ENABLE       (1u << 0)

#define UART_FSTAT_TX_FULL    (1u << 8)
#define UART_FSTAT_RX_EMPTY   (1u << 25)

#define TIMER_BASE       0x40000000u

#define TIMER_CTRL       (*(volatile uint32_t *)(TIMER_BASE + 0x00u))
#define TIMER_MTIME      (*(volatile uint32_t *)(TIMER_BASE + 0x08u))
#define TIMER_MTIMEH     (*(volatile uint32_t *)(TIMER_BASE + 0x0cu))
#define TIMER_MTIMECMP   (*(volatile uint32_t *)(TIMER_BASE + 0x10u))
#define TIMER_MTIMECMPH  (*(volatile uint32_t *)(TIMER_BASE + 0x14u))

#define TIMER_CTRL_ENABLE          (1u << 0)
#define TIMER_PERIOD_US            10000u
#define TIMER_LED_PERIOD_TICKS     50u

#define MSTATUS_MIE                (1u << 3)
#define MIE_MTIE                   (1u << 7)
#define MCAUSE_MACHINE_TIMER_IRQ   0x80000007u

#define GPIO_OUT (*(volatile uint32_t *)0x40008000u)

#define GPIO_FOREGROUND_MASK       0x7fu
#define GPIO_TIMER_LED             0x80u
#define GPIO_PATTERN_PERIOD_MS     100u

volatile uint32_t system_ticks;
volatile uint32_t timer_interrupt_count;
volatile uint64_t timer_next_compare;
volatile uint32_t last_mcause;
volatile uint32_t last_mepc;
volatile uint32_t last_mtval;
volatile uint32_t unexpected_trap_count;
volatile uint32_t uart_rx_count;
volatile uint32_t uart_tx_count;
volatile uint32_t uart_last_status;

static volatile uint32_t gpio_shadow;
static uint32_t timer_led_countdown;

static void uart_putc(uint8_t value)
{
    while ((UART_FSTAT & UART_FSTAT_TX_FULL) != 0u) {
    }

    UART_TX = value;
    ++uart_tx_count;
}

static void uart_puts(const char* text)
{
    while (*text != '\0') {
        uart_putc((uint8_t)*text);
        ++text;
    }
}

static void uart_put_hex32(uint32_t value)
{
    static const char hex_digits[] = "0123456789ABCDEF";

    uart_puts("0x");

    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc((uint8_t)hex_digits[(value >> (uint32_t)shift) & 0x0fu]);
    }
}

static int uart_getc_nonblocking(uint8_t* value)
{
    uart_last_status = UART_FSTAT;

    if ((uart_last_status & UART_FSTAT_RX_EMPTY) != 0u) {
        return 0;
    }

    *value = (uint8_t)UART_RX;
    ++uart_rx_count;
    return 1;
}

static void console_print_prompt(void)
{
    uart_puts("\r\n> ");
}

static void console_print_help(void)
{
    uart_puts("\r\nCommands:\r\n");
    uart_puts("  h or ?  help\r\n");
    uart_puts("  s       status\r\n");
    uart_puts("  v       version\r\n");
    uart_puts("Other characters are echoed.\r\n");
    uart_puts("> ");
}

static void console_print_version(void)
{
    uart_puts("\r\nHazard3 ULX3S timer + external UART console\r\n");
    uart_puts("> ");
}

static void console_print_status(void)
{
    uart_puts("\r\nsystem_ticks=");
    uart_put_hex32(system_ticks);
    uart_puts(" timer_irq_count=");
    uart_put_hex32(timer_interrupt_count);
    uart_puts(" unexpected_traps=");
    uart_put_hex32(unexpected_trap_count);
    uart_puts("\r\nlast_mcause=");
    uart_put_hex32(last_mcause);
    uart_puts(" last_mepc=");
    uart_put_hex32(last_mepc);
    uart_puts(" last_mtval=");
    uart_put_hex32(last_mtval);
    uart_puts("\r\nuart_rx_count=");
    uart_put_hex32(uart_rx_count);
    uart_puts(" uart_tx_count=");
    uart_put_hex32(uart_tx_count);
    uart_puts(" uart_fstat=");
    uart_put_hex32(UART_FSTAT);
    uart_puts("\r\n> ");
}

static void console_poll(void)
{
    uint8_t received;

    while (uart_getc_nonblocking(&received)) {
        switch (received) {
        case '\r':
        case '\n':
            console_print_prompt();
            break;

        case 'h':
        case 'H':
        case '?':
            console_print_help();
            break;

        case 's':
        case 'S':
            console_print_status();
            break;

        case 'v':
        case 'V':
            console_print_version();
            break;

        default:
            uart_putc(received);
            break;
        }
    }
}

static uint32_t interrupt_save(void)
{
    uint32_t mstatus;
    uint32_t mask = MSTATUS_MIE;

    __asm__ volatile (
        "csrrc %0, mstatus, %1"
        : "=r" (mstatus)
        : "r" (mask)
        : "memory"
    );

    return mstatus;
}

static void interrupt_restore(uint32_t mstatus)
{
    if ((mstatus & MSTATUS_MIE) != 0u) {
        uint32_t mask = MSTATUS_MIE;

        __asm__ volatile (
            "csrs mstatus, %0"
            :
            : "r" (mask)
            : "memory"
        );
    }
}

static void gpio_write_masked(uint32_t mask, uint32_t value)
{
    uint32_t saved_mstatus = interrupt_save();

    gpio_shadow = (gpio_shadow & ~mask) | (value & mask);
    GPIO_OUT = gpio_shadow;

    interrupt_restore(saved_mstatus);
}

static uint64_t timer_read(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do {
        high_before = TIMER_MTIMEH;
        low = TIMER_MTIME;
        high_after = TIMER_MTIMEH;
    } while (high_before != high_after);

    return ((uint64_t)high_after << 32) | low;
}

static void timer_set_compare(uint64_t compare)
{
    /*
     * Prevent a transient match while updating the 64-bit compare register
     * through its two 32-bit APB registers.
     */
    TIMER_MTIMECMPH = 0xffffffffu;
    TIMER_MTIMECMP = (uint32_t)compare;
    TIMER_MTIMECMPH = (uint32_t)(compare >> 32);
}

static void timer_init(void)
{
    uint32_t mask;

    TIMER_CTRL = TIMER_CTRL_ENABLE;

    timer_led_countdown = TIMER_LED_PERIOD_TICKS;
    timer_next_compare = timer_read() + TIMER_PERIOD_US;
    timer_set_compare(timer_next_compare);

    mask = MIE_MTIE;
    __asm__ volatile (
        "csrs mie, %0"
        :
        : "r" (mask)
        : "memory"
    );

    mask = MSTATUS_MIE;
    __asm__ volatile (
        "csrs mstatus, %0"
        :
        : "r" (mask)
        : "memory"
    );
}

void machine_trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    last_mcause = mcause;
    last_mepc = mepc;
    last_mtval = mtval;

    if (mcause == MCAUSE_MACHINE_TIMER_IRQ) {
        ++timer_interrupt_count;
        system_ticks += TIMER_PERIOD_US / 1000u;

        timer_next_compare += TIMER_PERIOD_US;
        timer_set_compare(timer_next_compare);

        if (--timer_led_countdown == 0u) {
            timer_led_countdown = TIMER_LED_PERIOD_TICKS;
            gpio_write_masked(GPIO_TIMER_LED, gpio_shadow ^ GPIO_TIMER_LED);
        }

        return;
    }

    ++unexpected_trap_count;
    timer_set_compare(UINT64_MAX);
    gpio_shadow = 0xffu;
    GPIO_OUT = gpio_shadow;

    for (;;) {
        __asm__ volatile ("nop");
    }
}

static void uart_init(void)
{
    /*
     * At a 50 MHz system clock with 8x UART oversampling:
     *
     *     50,000,000 / (115,200 * 8) = 54.253...
     *
     * The divider contains a 10-bit integer field in bits 13:4 and a
     * four-bit fractional field in bits 3:0. Use 54 + 4/16.
     */
    UART_DIV = (54u << 4) | 4u;
    UART_CSR = UART_CSR_ENABLE;
}

static void console_init(void)
{
    uart_puts("\r\nHazard3 ULX3S boot\r\n");
    uart_puts("UART: gp0 RX / gp1 TX, 115200 8N1\r\n");
    uart_puts("Timer: 10 ms machine interrupt\r\n");
    uart_puts("LED7: timer ISR, LED0-6: foreground\r\n");
    uart_puts("Type h or ? for help.\r\n");
    uart_puts("> ");
}

int main(void)
{
    uint32_t pattern = 1u;
    uint32_t next_pattern_tick;

    gpio_shadow = 0u;
    GPIO_OUT = gpio_shadow;

    uart_init();
    timer_init();
    console_init();

    next_pattern_tick = system_ticks + GPIO_PATTERN_PERIOD_MS;

    for (;;) {
        console_poll();

        if ((int32_t)(system_ticks - next_pattern_tick) >= 0) {
            gpio_write_masked(GPIO_FOREGROUND_MASK, pattern);

            pattern <<= 1;
            if (pattern == GPIO_TIMER_LED) {
                pattern = 1u;
            }

            next_pattern_tick += GPIO_PATTERN_PERIOD_MS;
        }
    }
}
