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

#define GPIO_OUT (*(volatile uint32_t *)0x40008000u)

volatile uint32_t uart_result;
volatile uint32_t uart_status;
volatile uint32_t uart_timeout;

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

    uint32_t pattern = 1u;

    for (;;) {
        GPIO_OUT = pattern;
        delay();

        pattern <<= 1;

        if (pattern == 0x100u) {
            pattern = 1u;
        }
    }
}
