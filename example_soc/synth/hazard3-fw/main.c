#include <stdint.h>

#define UART_BASE       0x40004000u

#define UART_CSR        (*(volatile uint32_t *)(UART_BASE + 0x00u))
#define UART_DIV        (*(volatile uint32_t *)(UART_BASE + 0x04u))
#define UART_FSTAT      (*(volatile uint32_t *)(UART_BASE + 0x08u))
#define UART_TX         (*(volatile uint32_t *)(UART_BASE + 0x0cu))
#define UART_RX         (*(volatile uint32_t *)(UART_BASE + 0x10u))

#define UART_CSR_ENABLE       (1u << 0)
#define UART_CSR_LOOPBACK     (1u << 8)

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

volatile uint32_t uart_result;
volatile uint32_t uart_status;
volatile uint32_t uart_timeout;

volatile uint32_t system_ticks;
volatile uint32_t timer_interrupt_count;
volatile uint64_t timer_next_compare;
volatile uint32_t last_mcause;
volatile uint32_t last_mepc;
volatile uint32_t last_mtval;
volatile uint32_t unexpected_trap_count;

static volatile uint32_t gpio_shadow;
static uint32_t timer_led_countdown;

static void uart_putc(uint8_t value)
{
    while ((UART_FSTAT & UART_FSTAT_TX_FULL) != 0u) {
    }

    UART_TX = value;
}

static int uart_getc_timeout(uint8_t* value)
{
    uint32_t timeout = 5000000u;

    while ((UART_FSTAT & UART_FSTAT_RX_EMPTY) != 0u) {
        if (--timeout == 0u) {
            uart_timeout = 1u;
            return 0;
        }
    }

    *value = (uint8_t)UART_RX;
    return 1;
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

static void delay(void)
{
    for (volatile uint32_t i = 0; i < 3000000u; ++i) {
    }
}

int main(void)
{
    uint8_t received = 0u;

    /*
     * At a 50 MHz system clock with 8x UART oversampling:
     *
     *     50,000,000 / (115,200 * 8) = 54.253...
     *
     * The divider contains a 10-bit integer field in bits 13:4 and a
     * four-bit fractional field in bits 3:0. Use 54 + 4/16.
     */
    UART_DIV = (54u << 4) | 4u;

    UART_CSR = UART_CSR_ENABLE | UART_CSR_LOOPBACK;

    uart_putc(0x48u); /* ASCII 'H' */

    if (uart_getc_timeout(&received)) {
        uart_result = received;
    }
    else {
        uart_result = 0xffffffffu;
    }

    uart_status = UART_FSTAT;

    gpio_shadow = 0u;
    GPIO_OUT = gpio_shadow;

    timer_init();

    uint32_t pattern = 1u;

    for (;;) {
        gpio_write_masked(GPIO_FOREGROUND_MASK, pattern);
        delay();

        pattern <<= 1;

        if (pattern == GPIO_TIMER_LED) {
            pattern = 1u;
        }
    }
}
