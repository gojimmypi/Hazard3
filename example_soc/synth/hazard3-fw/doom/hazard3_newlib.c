#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/types.h>

#include "hazard3_platform.h"

void* _sbrk(ptrdiff_t increment)
{
    void* previous_break = hazard3_sbrk(increment);
    if (previous_break == (void*)(intptr_t)-1) {
        errno = ENOMEM;
    }
    return previous_break;
}

void _init(void) {}
void _fini(void) {}

int _execve(const char* path, char* const argv[], char* const envp[])
{
    (void)path; (void)argv; (void)envp; errno = ENOSYS; return -1;
}
int _fork(void) { errno = ENOSYS; return -1; }
int _link(const char* existing_path, const char* new_path)
{
    (void)existing_path; (void)new_path; errno = ENOSYS; return -1;
}

int _mkdir(const char* path, mode_t mode)
{
    (void)path; (void)mode; errno = ENOSYS; return -1;
}

int mkdir(const char* path, mode_t mode)
{
    return _mkdir(path, mode);
}
int _wait(int* status) { (void)status; errno = ECHILD; return -1; }
int _close(int file) { (void)file; errno = EBADF; return -1; }

void _exit(int status)
{
    hazard3_console_puts("\r\nDoom image exited, status=");
    hazard3_console_put_hex32((uint32_t)status);
    hazard3_console_puts("\r\n");
    for (;;) { __asm__ volatile ("wfi"); }
}

int _fstat(int file, struct stat* status)
{
    (void)file;
    if (status == (struct stat*)0) { errno = EINVAL; return -1; }
    status->st_mode = S_IFCHR;
    return 0;
}
int _getpid(void) { return 1; }

int _gettimeofday(struct timeval* time_value, void* timezone_value)
{
    uint32_t milliseconds;
    (void)timezone_value;
    if (time_value == (struct timeval*)0) { errno = EINVAL; return -1; }
    milliseconds = hazard3_ticks_ms();
    time_value->tv_sec = (time_t)(milliseconds / 1000u);
    time_value->tv_usec = (suseconds_t)((milliseconds % 1000u) * 1000u);
    return 0;
}

int _isatty(int file) { return file >= 0 && file <= 2; }
int _kill(int process_id, int signal_number)
{
    (void)process_id; (void)signal_number; errno = EINVAL; return -1;
}
off_t _lseek(int file, off_t offset, int direction)
{
    (void)file; (void)offset; (void)direction; errno = ESPIPE; return (off_t)-1;
}
int _open(const char* path, int flags, ...)
{
    (void)path; (void)flags; errno = ENOENT; return -1;
}

ssize_t _read(int file, void* buffer, size_t byte_count)
{
    uint8_t* bytes = (uint8_t*)buffer;
    size_t received = 0u;
    if (file != 0 || buffer == (void*)0) { errno = EBADF; return -1; }
    while (received < byte_count) {
        uint8_t value;
        if (!hazard3_console_getc_nonblocking(&value)) { break; }
        bytes[received++] = value;
    }
    return (ssize_t)received;
}

int _stat(const char* path, struct stat* status)
{
    (void)path; (void)status; errno = ENOENT; return -1;
}

clock_t _times(struct tms* times_buffer)
{
    uint32_t milliseconds = hazard3_ticks_ms();
    if (times_buffer != (struct tms*)0) {
        times_buffer->tms_utime = (clock_t)milliseconds;
        times_buffer->tms_stime = 0;
        times_buffer->tms_cutime = 0;
        times_buffer->tms_cstime = 0;
    }
    return (clock_t)milliseconds;
}

int _unlink(const char* path) { (void)path; errno = ENOENT; return -1; }

ssize_t _write(int file, const void* buffer, size_t byte_count)
{
    const uint8_t* bytes = (const uint8_t*)buffer;
    if ((file != 1 && file != 2) || buffer == (const void*)0) {
        errno = EBADF; return -1;
    }
    for (size_t index = 0u; index < byte_count; ++index) {
        hazard3_console_putc(bytes[index]);
    }
    return (ssize_t)byte_count;
}
