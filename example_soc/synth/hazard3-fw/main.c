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

#define SDRAM_BASE                 0x20000000u
#define SDRAM_SIZE_BYTES           (64u * 1024u * 1024u)
#define SDRAM_BANK_BYTES           (16u * 1024u * 1024u)
#define SDRAM_BANK_COUNT           4u
#define SDRAM_QUICK_TEST_BYTES     (64u * 1024u)
#define SDRAM_FULL_TEST_BYTES      (1024u * 1024u)
#define SDRAM_RANDOM_TEST_BYTES    (1024u * 1024u)
#define SDRAM_RANDOM_TEST_PASSES   SDRAM_BANK_COUNT
#define SDRAM_SPARSE_POINT_COUNT   30u

#if (SDRAM_RANDOM_TEST_BYTES == 0u) || \
    ((SDRAM_RANDOM_TEST_BYTES & (SDRAM_RANDOM_TEST_BYTES - 1u)) != 0u)
#error "SDRAM_RANDOM_TEST_BYTES must be a nonzero power of two"
#endif

#if SDRAM_RANDOM_TEST_BYTES > SDRAM_BANK_BYTES
#error "SDRAM_RANDOM_TEST_BYTES must fit within one SDRAM bank"
#endif

#define SDRAM_PATTERN_ZERO         0u
#define SDRAM_PATTERN_ONES         1u
#define SDRAM_PATTERN_ADDRESS      2u
#define SDRAM_PATTERN_ADDRESS_INV  3u
#define SDRAM_PATTERN_COUNT        4u

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

volatile uint32_t sdram_test_runs;
volatile uint32_t sdram_failed_runs;
volatile uint32_t sdram_words_tested;
volatile uint32_t sdram_total_failures;
volatile uint32_t sdram_last_test_bytes;
volatile uint32_t sdram_last_elapsed_ms;
volatile uint32_t sdram_last_failures;
volatile uint32_t sdram_last_first_failure_addr;
volatile uint32_t sdram_last_first_failure_expected;
volatile uint32_t sdram_last_first_failure_actual;
volatile uint32_t sdram_last_passed;
volatile uint32_t sdram_random_passes_completed;
volatile uint32_t sdram_last_random_seed;
volatile uint32_t sdram_qualification_runs;
volatile uint32_t sdram_qualification_failures;
volatile uint32_t sdram_last_qualification_passed;
volatile uint32_t sdram_last_qualification_pass_mask;

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
    uart_puts("  m       destructive 1 MiB sequential SDRAM test\r\n");
    uart_puts("  a       sparse 64 MiB address/bank alias test\r\n");
    uart_puts("  r       pseudorandom 1 MiB test in each SDRAM bank\r\n");
    uart_puts("  q       complete SDRAM qualification suite\r\n");
    uart_puts("  s       status\r\n");
    uart_puts("  v       version\r\n");
    uart_puts("Other characters are echoed.\r\n");
    uart_puts("> ");
}

static void console_print_version(void)
{
    uart_puts("\r\nHazard3 ULX3S SDRAM qualification firmware\r\n");
    uart_puts("> ");
}

static void memory_barrier(void)
{
    __asm__ volatile ("fence rw, rw" ::: "memory");
}

static void sdram_record_failure(
    const volatile uint32_t* address,
    uint32_t expected,
    uint32_t actual)
{
    if (sdram_last_failures == 0u) {
        sdram_last_first_failure_addr = (uint32_t)(uintptr_t)address;
        sdram_last_first_failure_expected = expected;
        sdram_last_first_failure_actual = actual;
    }

    ++sdram_last_failures;
    ++sdram_total_failures;
}

static int sdram_check_word(
    const volatile uint32_t* address,
    uint32_t expected)
{
    uint32_t actual = *address;

    ++sdram_words_tested;

    if (actual != expected) {
        sdram_record_failure(address, expected, actual);
        return 0;
    }

    return 1;
}

static int sdram_width_test(void)
{
    volatile uint32_t* const word = (volatile uint32_t*)SDRAM_BASE;
    volatile uint16_t* const halfwords = (volatile uint16_t*)SDRAM_BASE;
    volatile uint8_t* const bytes = (volatile uint8_t*)SDRAM_BASE;
    int passed = 1;

    *word = 0x11223344u;
    memory_barrier();
    passed &= sdram_check_word(word, 0x11223344u);

    bytes[0] = 0xaau;
    memory_barrier();
    passed &= sdram_check_word(word, 0x112233aau);

    bytes[1] = 0xbbu;
    memory_barrier();
    passed &= sdram_check_word(word, 0x1122bbaau);

    bytes[2] = 0xccu;
    memory_barrier();
    passed &= sdram_check_word(word, 0x11ccbbaau);

    bytes[3] = 0xddu;
    memory_barrier();
    passed &= sdram_check_word(word, 0xddccbbaau);

    halfwords[1] = 0xeeffu;
    memory_barrier();
    passed &= sdram_check_word(word, 0xeeffbbaau);

    halfwords[0] = 0x5566u;
    memory_barrier();
    passed &= sdram_check_word(word, 0xeeff5566u);

    return passed;
}

static uint32_t sdram_pattern_value(uint32_t word_index, uint32_t pattern)
{
    uint32_t byte_address = SDRAM_BASE + word_index * sizeof(uint32_t);

    switch (pattern) {
    case SDRAM_PATTERN_ZERO:
        return 0x00000000u;

    case SDRAM_PATTERN_ONES:
        return 0xffffffffu;

    case SDRAM_PATTERN_ADDRESS:
        return byte_address ^ 0xa5a55a5au;

    default:
        return ~(byte_address ^ 0xa5a55a5au);
    }
}

static const char* sdram_pattern_name(uint32_t pattern)
{
    switch (pattern) {
    case SDRAM_PATTERN_ZERO:
        return "zero";

    case SDRAM_PATTERN_ONES:
        return "ones";

    case SDRAM_PATTERN_ADDRESS:
        return "address";

    default:
        return "inverse address";
    }
}

static int sdram_pattern_test(uint32_t byte_count, uint32_t pattern)
{
    volatile uint32_t* const words = (volatile uint32_t*)SDRAM_BASE;
    uint32_t word_count = byte_count / sizeof(uint32_t);
    uint32_t failures_before = sdram_last_failures;

    for (uint32_t i = 0u; i < word_count; ++i) {
        words[i] = sdram_pattern_value(i, pattern);
    }

    memory_barrier();

    for (uint32_t i = 0u; i < word_count; ++i) {
        (void)sdram_check_word(&words[i], sdram_pattern_value(i, pattern));
    }

    return sdram_last_failures == failures_before;
}

static uint32_t sdram_test_begin(uint32_t byte_count)
{
    ++sdram_test_runs;
    sdram_last_test_bytes = byte_count;
    sdram_last_elapsed_ms = 0u;
    sdram_last_failures = 0u;
    sdram_last_first_failure_addr = 0u;
    sdram_last_first_failure_expected = 0u;
    sdram_last_first_failure_actual = 0u;
    sdram_last_passed = 0u;

    return system_ticks;
}

static int sdram_test_finish(uint32_t start_ticks, int passed)
{
    sdram_last_elapsed_ms = system_ticks - start_ticks;
    sdram_last_passed = passed && sdram_last_failures == 0u;

    uart_puts("  result: ");
    if (sdram_last_passed != 0u) {
        uart_puts("PASS");
    } else {
        ++sdram_failed_runs;
        uart_puts("FAIL failures=");
        uart_put_hex32(sdram_last_failures);
        uart_puts("\r\n  first failure: addr=");
        uart_put_hex32(sdram_last_first_failure_addr);
        uart_puts(" expected=");
        uart_put_hex32(sdram_last_first_failure_expected);
        uart_puts(" actual=");
        uart_put_hex32(sdram_last_first_failure_actual);
    }

    uart_puts(" elapsed_ms=");
    uart_put_hex32(sdram_last_elapsed_ms);
    uart_puts("\r\n");

    return sdram_last_passed != 0u;
}

static uint32_t sdram_sparse_offset(uint32_t point)
{
    if (point == 0u) {
        return 0u;
    }

    if (point <= 24u) {
        return 1u << (point + 1u);
    }

    switch (point) {
    case 25u:
        return 0x00fffffcu;

    case 26u:
        return 0x01fffffcu;

    case 27u:
        return 0x02fffffcu;

    case 28u:
        return 0x03000000u;

    default:
        return SDRAM_SIZE_BYTES - sizeof(uint32_t);
    }
}

static uint32_t sdram_sparse_value(uint32_t point, int inverted)
{
    uint32_t address = SDRAM_BASE + sdram_sparse_offset(point);
    uint32_t value = address ^ (0x9e3779b9u * (point + 1u)) ^ 0x6d2b79f5u;

    return inverted ? ~value : value;
}

static int sdram_sparse_phase(int inverted)
{
    uint32_t failures_before = sdram_last_failures;

    /*
     * The point set contains the base address, every word-address bit from
     * byte-address bit 2 through bit 25, the last word of every 16 MiB bank,
     * and the base of bank 3. Writing every point before reading any point
     * detects stuck address lines and aliasing between rows, columns, or banks.
     */
    for (uint32_t point = 0u; point < SDRAM_SPARSE_POINT_COUNT; ++point) {
        volatile uint32_t* address = (volatile uint32_t*)(uintptr_t)(
            SDRAM_BASE + sdram_sparse_offset(point));

        *address = sdram_sparse_value(point, inverted);
    }

    memory_barrier();

    for (uint32_t point = 0u; point < SDRAM_SPARSE_POINT_COUNT; ++point) {
        volatile uint32_t* address = (volatile uint32_t*)(uintptr_t)(
            SDRAM_BASE + sdram_sparse_offset(point));

        (void)sdram_check_word(
            address,
            sdram_sparse_value(point, inverted));
    }

    return sdram_last_failures == failures_before;
}

static int sdram_run_sparse_test(void)
{
    uint32_t start_ticks;
    int passed;
    int phase_passed;

    uart_puts("\r\nSDRAM sparse 64 MiB address/bank alias test: base=");
    uart_put_hex32(SDRAM_BASE);
    uart_puts(" bytes=");
    uart_put_hex32(SDRAM_SIZE_BYTES);
    uart_puts(" points=");
    uart_put_hex32(SDRAM_SPARSE_POINT_COUNT);
    uart_puts("\r\n  unique values: ");

    start_ticks = sdram_test_begin(SDRAM_SIZE_BYTES);
    passed = sdram_sparse_phase(0);
    uart_puts(passed ? "PASS\r\n" : "FAIL\r\n");

    uart_puts("  inverse values: ");
    phase_passed = sdram_sparse_phase(1);
    uart_puts(phase_passed ? "PASS\r\n" : "FAIL\r\n");
    passed &= phase_passed;

    return sdram_test_finish(start_ticks, passed);
}

static uint32_t sdram_prng_next(uint32_t state)
{
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static uint32_t sdram_random_value(uint32_t state, uint32_t byte_address)
{
    return state ^ byte_address ^ 0xa5a55a5au;
}

static int sdram_random_pass(
    uint32_t base_offset,
    uint32_t byte_count,
    uint32_t seed)
{
    volatile uint32_t* const words = (volatile uint32_t*)(uintptr_t)(
        SDRAM_BASE + base_offset);
    uint32_t word_count = byte_count / sizeof(uint32_t);
    uint32_t word_mask = word_count - 1u;
    uint32_t stride = (seed | 1u) & word_mask;
    uint32_t start_index = (seed >> 16) & word_mask;
    uint32_t state = seed;
    uint32_t failures_before = sdram_last_failures;

    if (stride == 0u) {
        stride = 1u;
    }

    /*
     * word_count is a power of two and stride is odd, so this modular walk
     * visits every word exactly once. It stresses nonsequential row and
     * column changes without needing a permutation table in internal SRAM.
     */
    for (uint32_t i = 0u; i < word_count; ++i) {
        uint32_t word_index = (start_index + i * stride) & word_mask;

        uint32_t byte_address = SDRAM_BASE + base_offset +
            word_index * sizeof(uint32_t);

        state = sdram_prng_next(state);
        words[word_index] = sdram_random_value(state, byte_address);
    }

    memory_barrier();
    state = seed;

    for (uint32_t i = 0u; i < word_count; ++i) {
        uint32_t word_index = (start_index + i * stride) & word_mask;

        uint32_t byte_address = SDRAM_BASE + base_offset +
            word_index * sizeof(uint32_t);

        state = sdram_prng_next(state);
        (void)sdram_check_word(
            &words[word_index],
            sdram_random_value(state, byte_address));
    }

    return sdram_last_failures == failures_before;
}

static int sdram_run_random_test(void)
{
    uint32_t start_ticks;
    int passed = 1;

    uart_puts("\r\nSDRAM pseudorandom test: base=");
    uart_put_hex32(SDRAM_BASE);
    uart_puts(" bytes_per_bank=");
    uart_put_hex32(SDRAM_RANDOM_TEST_BYTES);
    uart_puts(" banks=");
    uart_put_hex32(SDRAM_RANDOM_TEST_PASSES);
    uart_puts("\r\n");

    start_ticks = sdram_test_begin(
        SDRAM_RANDOM_TEST_BYTES * SDRAM_RANDOM_TEST_PASSES);

    for (uint32_t pass = 0u; pass < SDRAM_RANDOM_TEST_PASSES; ++pass) {
        uint32_t base_offset = pass * SDRAM_BANK_BYTES;
        uint32_t seed = 0x13579bdfu ^ (0x9e3779b9u * (pass + 1u));
        int pass_passed;

        if (seed == 0u) {
            seed = 1u;
        }

        sdram_last_random_seed = seed;
        uart_puts("  pass ");
        uart_put_hex32(pass + 1u);
        uart_puts(" base=");
        uart_put_hex32(SDRAM_BASE + base_offset);
        uart_puts(" seed=");
        uart_put_hex32(seed);
        uart_puts(": ");

        pass_passed = sdram_random_pass(
            base_offset,
            SDRAM_RANDOM_TEST_BYTES,
            seed);
        uart_puts(pass_passed ? "PASS\r\n" : "FAIL\r\n");
        passed &= pass_passed;
        ++sdram_random_passes_completed;
    }

    return sdram_test_finish(start_ticks, passed);
}

static int sdram_run_test(uint32_t byte_count, const char* description)
{
    uint32_t start_ticks;
    int passed;

    uart_puts("\r\n");
    uart_puts(description);
    uart_puts(": base=");
    uart_put_hex32(SDRAM_BASE);
    uart_puts(" bytes=");
    uart_put_hex32(byte_count);
    uart_puts("\r\n  access widths: ");

    start_ticks = sdram_test_begin(byte_count);
    passed = sdram_width_test();
    uart_puts(passed ? "PASS\r\n" : "FAIL\r\n");

    for (uint32_t pattern = 0u; pattern < SDRAM_PATTERN_COUNT; ++pattern) {
        int pattern_passed;

        uart_puts("  pattern ");
        uart_puts(sdram_pattern_name(pattern));
        uart_puts(": ");

        pattern_passed = sdram_pattern_test(byte_count, pattern);
        uart_puts(pattern_passed ? "PASS\r\n" : "FAIL\r\n");
        passed &= pattern_passed;
    }

    return sdram_test_finish(start_ticks, passed);
}

static int sdram_run_qualification(void)
{
    int sequential_passed;
    int sparse_passed;
    int random_passed;
    int passed;

    ++sdram_qualification_runs;
    sdram_last_qualification_pass_mask = 0u;
    uart_puts("\r\n=== SDRAM qualification suite ===\r\n");

    sequential_passed = sdram_run_test(
        SDRAM_FULL_TEST_BYTES,
        "SDRAM destructive 1 MiB sequential test");
    sparse_passed = sdram_run_sparse_test();
    random_passed = sdram_run_random_test();

    if (sequential_passed) {
        sdram_last_qualification_pass_mask |= 1u << 0;
    }
    if (sparse_passed) {
        sdram_last_qualification_pass_mask |= 1u << 1;
    }
    if (random_passed) {
        sdram_last_qualification_pass_mask |= 1u << 2;
    }

    passed = sequential_passed && sparse_passed && random_passed;
    sdram_last_qualification_passed = passed != 0;
    if (!passed) {
        ++sdram_qualification_failures;
    }

    uart_puts("=== SDRAM qualification: ");
    uart_puts(passed ? "PASS" : "FAIL");
    uart_puts(" ===\r\n");

    return passed;
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
    uart_puts("\r\nsdram_runs=");
    uart_put_hex32(sdram_test_runs);
    uart_puts(" failed_runs=");
    uart_put_hex32(sdram_failed_runs);
    uart_puts(" total_failures=");
    uart_put_hex32(sdram_total_failures);
    uart_puts(" words_checked=");
    uart_put_hex32(sdram_words_tested);
    uart_puts("\r\nsdram_last_bytes=");
    uart_put_hex32(sdram_last_test_bytes);
    uart_puts(" last_failures=");
    uart_put_hex32(sdram_last_failures);
    uart_puts(" elapsed_ms=");
    uart_put_hex32(sdram_last_elapsed_ms);
    uart_puts(" result=");
    uart_puts(sdram_last_passed != 0u ? "PASS" : "FAIL");
    uart_puts("\r\nrandom_passes=");
    uart_put_hex32(sdram_random_passes_completed);
    uart_puts(" last_random_seed=");
    uart_put_hex32(sdram_last_random_seed);
    uart_puts(" qualification_runs=");
    uart_put_hex32(sdram_qualification_runs);
    uart_puts("\r\nqualification_failures=");
    uart_put_hex32(sdram_qualification_failures);
    uart_puts(" pass_mask=");
    uart_put_hex32(sdram_last_qualification_pass_mask);
    uart_puts(" last_qualification=");
    if (sdram_qualification_runs == 0u) {
        uart_puts("NOT RUN");
    } else {
        uart_puts(sdram_last_qualification_passed != 0u ? "PASS" : "FAIL");
    }

    if (sdram_last_failures != 0u) {
        uart_puts("\r\nsdram_first_failure_addr=");
        uart_put_hex32(sdram_last_first_failure_addr);
        uart_puts(" expected=");
        uart_put_hex32(sdram_last_first_failure_expected);
        uart_puts(" actual=");
        uart_put_hex32(sdram_last_first_failure_actual);
    }

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

        case 'm':
        case 'M':
            (void)sdram_run_test(
                SDRAM_FULL_TEST_BYTES,
                "SDRAM destructive 1 MiB sequential test");
            uart_puts("> ");
            break;

        case 'a':
        case 'A':
            (void)sdram_run_sparse_test();
            uart_puts("> ");
            break;

        case 'r':
        case 'R':
            (void)sdram_run_random_test();
            uart_puts("> ");
            break;

        case 'q':
        case 'Q':
            (void)sdram_run_qualification();
            uart_puts("> ");
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
    uart_puts("SDRAM: AHB target at 0x20000000, 64 MiB qualification map\r\n");
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

    (void)sdram_run_test(SDRAM_QUICK_TEST_BYTES, "SDRAM boot quick test");
    uart_puts("Type h or ? for help.\r\n> ");

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
