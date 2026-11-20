#ifndef FOXOS_LIBC_H
#define FOXOS_LIBC_H

#define FOX_O_RDONLY 0
#define FOX_O_WRONLY_CREATE_TRUNC 1
#define FOX_DT_DIRECTORY 1
#define FOX_DT_FILE 2

struct FoxStat {
    unsigned long type;
    unsigned long size;
};

struct FoxDirent {
    unsigned int id;
    unsigned char type;
    char name[27];
};

long fox_read(int fd, void *buffer, unsigned long count);
long fox_write(int fd, const void *buffer, unsigned long count);
long fox_open(const char *name);
long fox_open_flags(const char *name, int flags);
long fox_close(int fd);
long fox_stat(const char *name, struct FoxStat *status);
long fox_mkdir(const char *name);
long fox_readdir(int fd, struct FoxDirent *entry);
long fox_pipe(int descriptors[2]);
long fox_dup2(int old_fd, int new_fd);
long fox_exec(const char *name, int argc, const char *const argv[],
              const char *const envp[]);
long fox_fork(void);
long fox_wait(void);
long fox_yield(void);
unsigned long long fox_ticks(void);
__attribute__((noreturn)) void fox_exit(int status);
long fox_getpid(void);
unsigned long fox_strlen(const char *text);
int fox_strcmp(const char *left, const char *right);
void fox_puts(const char *text);

#endif
