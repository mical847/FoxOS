#include "libc.h"

__attribute__((noreturn, section(".text.start")))
void _start(int argc, char **argv, char **envp)
{
    int index;

    fox_puts("Arguments received:\n");
    for (index = 0; index < argc; index++) {
        fox_puts(argv[index]);
        fox_puts("\n");
    }
    fox_puts("Environment received:\n");
    for (index = 0; envp[index] != 0; index++) {
        fox_puts(envp[index]);
        fox_puts("\n");
    }
    fox_exit(0);
}
