#include "libc.h"

__attribute__((noreturn, section(".text.start")))
void _start(void)
{
    fox_puts("Hello from a separate ELF program in the initramfs!\n");
    fox_exit(0);
}
