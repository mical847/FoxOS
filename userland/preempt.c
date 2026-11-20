#include "libc.h"

__attribute__((noreturn, section(".text.start")))
void _start(void)
{
    unsigned long long before = fox_ticks();
    volatile unsigned long long checksum = 0;
    unsigned long long index;

    for (index = 0; index < 20000000; index++) {
        checksum += index;
    }

    if (fox_ticks() > before && checksum != 0) {
        fox_puts("Timer preemption passed: ticks advanced during busy loop.\n");
        fox_exit(0);
    }

    fox_puts("Timer preemption failed: no timer ticks observed.\n");
    fox_exit(1);
}
