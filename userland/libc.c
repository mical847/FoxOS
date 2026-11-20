#include "libc.h"

static long syscall3(long number, long arg1, long arg2, long arg3)
{
    long result;

    __asm__ volatile (
        "int $0x80"
        : "=a" (result)
        : "a" (number), "D" (arg1), "S" (arg2), "d" (arg3)
        : "rcx", "r11", "memory"
    );

    return result;
}

static long syscall4(long number, long arg1, long arg2, long arg3, long arg4)
{
    long result;
    register long fourth_argument __asm__("r10") = arg4;

    __asm__ volatile (
        "int $0x80"
        : "=a" (result)
        : "a" (number), "D" (arg1), "S" (arg2), "d" (arg3),
          "r" (fourth_argument)
        : "rcx", "r11", "memory"
    );

    return result;
}

long fox_read(int fd, void *buffer, unsigned long count)
{
    long result;

    do {
        result = syscall3(0, fd, (long)buffer, (long)count);
        if (result == -11) {
            fox_yield();
        }
    } while (result == -11);

    return result;
}

long fox_write(int fd, const void *buffer, unsigned long count)
{
    const char *bytes = buffer;
    unsigned long written = 0;

    while (written < count) {
        long result = syscall3(1, fd, (long)(bytes + written), count - written);
        if (result == -11) {
            fox_yield();
            continue;
        }
        if (result <= 0) {
            return written != 0 ? (long)written : result;
        }
        written += (unsigned long)result;
    }

    return (long)written;
}

long fox_open(const char *name)
{
    return syscall3(2, (long)name, 0, 0);
}

long fox_open_flags(const char *name, int flags)
{
    return syscall3(2, (long)name, flags, 0);
}

long fox_close(int fd)
{
    return syscall3(3, fd, 0, 0);
}

long fox_stat(const char *name, struct FoxStat *status)
{
    return syscall3(4, (long)name, (long)status, 0);
}

long fox_mkdir(const char *name)
{
    return syscall3(83, (long)name, 0, 0);
}

long fox_readdir(int fd, struct FoxDirent *entry)
{
    return syscall3(78, fd, (long)entry, sizeof(*entry));
}

long fox_pipe(int descriptors[2])
{
    return syscall3(22, (long)descriptors, 0, 0);
}

long fox_dup2(int old_fd, int new_fd)
{
    return syscall3(33, old_fd, new_fd, 0);
}

long fox_exec(const char *name, int argc, const char *const argv[],
              const char *const envp[])
{
    return syscall4(59, (long)name, (long)argv, argc, (long)envp);
}

long fox_fork(void)
{
    return syscall3(57, 0, 0, 0);
}

long fox_wait(void)
{
    return syscall3(61, 0, 0, 0);
}

long fox_yield(void)
{
    return syscall3(24, 0, 0, 0);
}

unsigned long long fox_ticks(void)
{
    return (unsigned long long)syscall3(96, 0, 0, 0);
}

long fox_getpid(void)
{
    return syscall3(39, 0, 0, 0);
}

__attribute__((noreturn))
void fox_exit(int status)
{
    syscall3(60, status, 0, 0);
    for (;;) {
        __asm__ volatile ("pause");
    }
}

unsigned long fox_strlen(const char *text)
{
    unsigned long length = 0;
    while (text[length] != '\0') {
        length++;
    }
    return length;
}

int fox_strcmp(const char *left, const char *right)
{
    while (*left != '\0' && *left == *right) {
        left++;
        right++;
    }
    return (unsigned char)*left - (unsigned char)*right;
}

void fox_puts(const char *text)
{
    fox_write(1, text, fox_strlen(text));
}
