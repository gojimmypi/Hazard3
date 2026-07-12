#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "hazard3_platform.h"

int _close(int file)
{
    (void)file;
    errno = EBADF;
    return -1;
}

void _exit(int status)
{
    hazard3_console_puts("\r\nProgram exited, status=");
    hazard3_console_put_hex32((uint32_t)status);
    hazard3_console_puts("\r\n");

    for (;;) {
        __asm__ volatile ("wfi");
    }
}

int _fstat(int file, struct stat* status)
{
    (void)file;

    if (status == (struct stat*)0) {
        errno = EINVAL;
        return -1;
    }

    status->st_mode = S_IFCHR;
    return 0;
}

int _getpid(void)
{
    return 1;
}

int _isatty(int file)
{
    return file >= 0 && file <= 2;
}

int _kill(int process_id, int signal_number)
{
    (void)process_id;
    (void)signal_number;
    errno = EINVAL;
    return -1;
}

off_t _lseek(int file, off_t offset, int direction)
{
    (void)file;
    (void)offset;
    (void)direction;
    errno = ESPIPE;
    return (off_t)-1;
}

ssize_t _read(int file, void* buffer, size_t byte_count)
{
    uint8_t* bytes = (uint8_t*)buffer;
    size_t received = 0u;

    if (file != 0 || buffer == (void*)0) {
        errno = EBADF;
        return -1;
    }

    while (received < byte_count) {
        uint8_t value;

        if (!hazard3_console_getc_nonblocking(&value)) {
            break;
        }

        bytes[received++] = value;
    }

    return (ssize_t)received;
}

ssize_t _write(int file, const void* buffer, size_t byte_count)
{
    const uint8_t* bytes = (const uint8_t*)buffer;
    size_t index;

    if ((file != 1 && file != 2) || buffer == (const void*)0) {
        errno = EBADF;
        return -1;
    }

    for (index = 0u; index < byte_count; ++index) {
        hazard3_console_putc(bytes[index]);
    }

    return (ssize_t)byte_count;
}
