#include "libc.h"

__attribute__((noreturn, section(".text.start")))
void _start(void)
{
    char buffer[128];
    long count;

    while ((count = fox_read(0, buffer, sizeof(buffer))) > 0) {
        if (fox_write(1, buffer, (unsigned long)count) < 0) {
            fox_exit(1);
        }
    }
    fox_exit(count < 0 ? 1 : 0);
}
