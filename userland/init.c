#include "libc.h"

enum {
    SHELL_PATH_SIZE = 128,
    JOINED_PATH_SIZE = SHELL_PATH_SIZE * 2
};

static char current_directory[SHELL_PATH_SIZE] = "/";
static char path_environment[SHELL_PATH_SIZE] = "PATH=/";
static char exec_candidate[SHELL_PATH_SIZE];
static char resolved_path[SHELL_PATH_SIZE];
static char joined_path[JOINED_PATH_SIZE];

static const char *const shell_environment[] = {
    "FOXOS=FoxOS",
    path_environment,
    0
};

static int copy_string(char *destination, const char *source,
                       unsigned long capacity)
{
    unsigned long index;

    for (index = 0; index < capacity; index++) {
        destination[index] = source[index];
        if (source[index] == '\0') {
            return 1;
        }
    }

    return 0;
}

static int append_component(char *path, unsigned long *length,
                            const char *component, unsigned long size)
{
    unsigned long index;

    if (size == 0 || size > 19) {
        return 0;
    }
    if (*length > 1) {
        if (*length + size + 1 >= SHELL_PATH_SIZE) {
            return 0;
        }
        path[(*length)++] = '/';
    } else if (*length + size >= SHELL_PATH_SIZE) {
        return 0;
    }

    for (index = 0; index < size; index++) {
        path[(*length)++] = component[index];
    }
    path[*length] = '\0';
    return 1;
}

static int normalize_components(const char *source, char *path,
                                unsigned long *length)
{
    const char *component;
    const char *cursor = source;

    while (*cursor != '\0') {
        unsigned long size;

        while (*cursor == '/') {
            cursor++;
        }
        if (*cursor == '\0') {
            break;
        }
        component = cursor;
        while (*cursor != '\0' && *cursor != '/') {
            cursor++;
        }
        size = (unsigned long)(cursor - component);

        if (size == 1 && component[0] == '.') {
            continue;
        }
        if (size == 2 && component[0] == '.' && component[1] == '.') {
            while (*length > 1 && path[*length - 1] != '/') {
                (*length)--;
            }
            if (*length > 1) {
                (*length)--;
            }
            path[*length] = '\0';
            continue;
        }
        if (!append_component(path, length, component, size)) {
            return 0;
        }
    }

    return 1;
}

static int resolve_path(const char *input, char *path)
{
    unsigned long length = 1;
    unsigned long index;

    path[0] = '/';
    path[1] = '\0';
    if (input[0] != '/' &&
        !normalize_components(current_directory, path, &length)) {
        return 0;
    }
    if (!normalize_components(input, path, &length)) {
        return 0;
    }
    if (length > 1) {
        index = 1;
        while (index < length && path[index] != '/') {
            index++;
        }
        if (index == length) {
            for (index = 1; index <= length; index++) {
                path[index - 1] = path[index];
            }
        }
    }
    return 1;
}

static int has_slash(const char *text)
{
    while (*text != '\0') {
        if (*text++ == '/') {
            return 1;
        }
    }
    return 0;
}

static int split_arguments(char *line, const char *arguments[8])
{
    char *cursor = line;
    int count = 0;

    while (*cursor != '\0') {
        while (*cursor == ' ') {
            cursor++;
        }
        if (*cursor == '\0') {
            break;
        }
        if (count == 8) {
            return -1;
        }

        arguments[count++] = cursor;
        while (*cursor != '\0' && *cursor != ' ') {
            cursor++;
        }
        if (*cursor == ' ') {
            *cursor++ = '\0';
        }
    }

    return count;
}

static int build_path_candidate(const char *directory, const char *program,
                                char *candidate)
{
    unsigned long length;

    if (!resolve_path(directory, resolved_path)) {
        return 0;
    }
    if (fox_strcmp(resolved_path, "/") == 0) {
        return copy_string(candidate, program, SHELL_PATH_SIZE);
    }

    length = fox_strlen(resolved_path);
    if (length + 1 >= SHELL_PATH_SIZE ||
        !copy_string(candidate, resolved_path, SHELL_PATH_SIZE)) {
        return 0;
    }
    candidate[length++] = '/';
    return copy_string(candidate + length, program,
                       SHELL_PATH_SIZE - length);
}

static void execute_child(const char *const arguments[], int count)
{
    const char *program = arguments[0];
    const char *path;
    long result = -2;

    if (has_slash(program)) {
        if (resolve_path(program, exec_candidate)) {
            result = fox_exec(exec_candidate, count, arguments,
                              shell_environment);
        }
    } else {
        path = path_environment + 5;
        while (result < 0) {
            const char *directory = path;
            unsigned long directory_length = 0;

            while (path[directory_length] != '\0' &&
                   path[directory_length] != ':') {
                directory_length++;
            }
            if (directory_length == 0) {
                if (!copy_string(joined_path, ".", sizeof(joined_path))) {
                    break;
                }
                directory = joined_path;
            } else {
                if (directory_length >= sizeof(joined_path)) {
                    break;
                }
                {
                    unsigned long index;
                    for (index = 0; index < directory_length; index++) {
                        joined_path[index] = path[index];
                    }
                }
                joined_path[directory_length] = '\0';
                directory = joined_path;
            }

            if (build_path_candidate(directory, program, exec_candidate)) {
                result = fox_exec(exec_candidate, count, arguments,
                                  shell_environment);
            }
            if (path[directory_length] == '\0') {
                break;
            }
            path += directory_length + 1;
        }
    }

    if (result == -22) {
        fox_puts("Invalid program arguments or environment.\n");
    } else {
        fox_puts("Program not found or invalid ELF.\n");
    }
    fox_exit(127);
}

static void run_pipeline(char *line, char *separator)
{
    const char *left_arguments[8];
    const char *right_arguments[8];
    int descriptors[2];
    int left_count;
    int right_count;
    long producer;
    long consumer;

    *separator = '\0';
    left_count = split_arguments(line, left_arguments);
    right_count = split_arguments(separator + 1, right_arguments);
    if (left_count <= 0 || right_count <= 0) {
        fox_puts("Usage: program | program\n");
        return;
    }
    if (fox_pipe(descriptors) < 0) {
        fox_puts("Unable to create pipe.\n");
        return;
    }

    producer = fox_fork();
    if (producer < 0) {
        fox_close(descriptors[0]);
        fox_close(descriptors[1]);
        fox_puts("Unable to create process.\n");
        return;
    }
    if (producer == 0) {
        fox_close(descriptors[0]);
        if (fox_dup2(descriptors[1], 1) < 0) {
            fox_exit(126);
        }
        fox_close(descriptors[1]);
        execute_child(left_arguments, left_count);
    }

    consumer = fox_fork();
    if (consumer < 0) {
        fox_close(descriptors[0]);
        fox_close(descriptors[1]);
        fox_puts("Unable to create process.\n");
        return;
    }
    if (consumer == 0) {
        fox_close(descriptors[1]);
        if (fox_dup2(descriptors[0], 0) < 0) {
            fox_exit(126);
        }
        fox_close(descriptors[0]);
        execute_child(right_arguments, right_count);
    }

    fox_close(descriptors[0]);
    fox_close(descriptors[1]);
    if (fox_wait() < 0 || fox_wait() < 0) {
        fox_puts("Process wait failed.\n");
    }
}

static void run_command(char *line)
{
    const char *arguments[8];
    char *separator = 0;
    char *cursor;
    int count;
    long child;

    for (cursor = line; *cursor != '\0'; cursor++) {
        if (*cursor == '|') {
            if (separator != 0) {
                fox_puts("Only one pipe is supported per command.\n");
                return;
            }
            separator = cursor;
        }
    }
    if (separator != 0) {
        run_pipeline(line, separator);
        return;
    }

    count = split_arguments(line, arguments);
    if (count < 0) {
        fox_puts("Too many arguments (maximum 8).\n");
        return;
    }
    if (count == 0) {
        return;
    }

    child = fox_fork();
    if (child < 0) {
        fox_puts("Unable to create process.\n");
    } else if (child == 0) {
        execute_child(arguments, count);
    } else if (fox_wait() < 0) {
        fox_puts("Process wait failed.\n");
    }
}

static char *skip_spaces(char *text)
{
    while (*text == ' ') {
        text++;
    }
    return text;
}

static void print_unsigned(unsigned long value)
{
    char digits[20];
    unsigned long count = 0;
    unsigned long index;

    do {
        digits[count++] = (char)('0' + value % 10);
        value /= 10;
    } while (value != 0 && count < sizeof(digits));

    for (index = count; index > 0; index--) {
        fox_write(1, &digits[index - 1], 1);
    }
}

static void list_directory(char *path)
{
    long fd;

    if (!resolve_path(path, resolved_path)) {
        fox_puts("Path is too long or contains an invalid component.\n");
        return;
    }
    fd = fox_open(resolved_path);

    if (fd < 0) {
        fox_puts("Directory not found or storage unavailable.\n");
        return;
    }

    for (;;) {
        struct FoxDirent entry;
        long result = fox_readdir((int)fd, &entry);

        if (result == 0) {
            break;
        }
        if (result < 0) {
            fox_puts("Not a directory.\n");
            break;
        }
        fox_puts(entry.name);
        if (entry.type == FOX_DT_DIRECTORY) {
            fox_puts("/");
        }
        fox_puts("\n");
    }
    fox_close((int)fd);
}

static void show_file_status(char *path)
{
    struct FoxStat status;

    if (!resolve_path(path, resolved_path)) {
        fox_puts("Path is too long or contains an invalid component.\n");
        return;
    }
    if (fox_stat(resolved_path, &status) < 0) {
        fox_puts("File or directory not found.\n");
        return;
    }
    fox_puts(status.type == FOX_DT_DIRECTORY ? "directory, " : "file, ");
    fox_puts("size ");
    print_unsigned(status.size);
    fox_puts(" bytes\n");
}

static void make_directory(char *path)
{
    if (!resolve_path(path, resolved_path)) {
        fox_puts("Path is too long or contains an invalid component.\n");
        return;
    }
    if (fox_mkdir(resolved_path) < 0) {
        fox_puts("Could not create directory.\n");
    } else {
        fox_puts("Directory created.\n");
    }
}

static void write_file(char *line)
{
    char *path = skip_spaces(&line[6]);
    char *content = path;
    long fd;
    long result;

    while (*content != '\0' && *content != ' ') {
        content++;
    }
    if (*content == '\0') {
        fox_puts("Usage: write <path> <text>\n");
        return;
    }
    *content++ = '\0';
    content = skip_spaces(content);
    if (!resolve_path(path, resolved_path)) {
        fox_puts("Path is too long or contains an invalid component.\n");
        return;
    }
    fd = fox_open_flags(resolved_path, FOX_O_WRONLY_CREATE_TRUNC);
    if (fd < 0) {
        fox_puts("Could not open file for writing.\n");
        return;
    }
    result = fox_write((int)fd, content, fox_strlen(content));
    fox_close((int)fd);
    if (result < 0) {
        fox_puts("File write failed.\n");
        return;
    }
    fox_puts("Wrote ");
    print_unsigned((unsigned long)result);
    fox_puts(" bytes.\n");
}

static void change_directory(char *path)
{
    struct FoxStat status;
    unsigned long length;
    unsigned long index;

    if (*path == '\0') {
        path = "/";
    }
    if (!resolve_path(path, resolved_path)) {
        fox_puts("Path is too long or contains an invalid component.\n");
        return;
    }
    if (fox_stat(resolved_path, &status) < 0 ||
        status.type != FOX_DT_DIRECTORY) {
        fox_puts("Directory not found.\n");
        return;
    }
    if (resolved_path[0] != '/') {
        length = fox_strlen(resolved_path);
        for (index = length + 1; index > 0; index--) {
            resolved_path[index] = resolved_path[index - 1];
        }
        resolved_path[0] = '/';
    }
    if (!copy_string(current_directory, resolved_path,
                     sizeof(current_directory))) {
        fox_puts("Directory path is too long.\n");
    }
}

static void show_file(char *path)
{
    struct FoxStat status;
    char buffer[128];
    long fd;
    long count;
    int failed = 0;

    if (!resolve_path(path, resolved_path)) {
        fox_puts("Path is too long or contains an invalid component.\n");
        return;
    }
    if (fox_stat(resolved_path, &status) < 0 ||
        status.type != FOX_DT_FILE) {
        fox_puts("File not found.\n");
        return;
    }
    fd = fox_open(resolved_path);
    if (fd < 0) {
        fox_puts("Could not open file.\n");
        return;
    }
    while ((count = fox_read((int)fd, buffer, sizeof(buffer))) > 0) {
        if (fox_write(1, buffer, (unsigned long)count) < 0) {
            failed = 1;
            break;
        }
    }
    if (count < 0) {
        failed = 1;
    }
    fox_close((int)fd);
    if (failed) {
        fox_puts("\nFile read failed.\n");
    }
}

static void set_path(char *value)
{
    unsigned long length = fox_strlen(value);

    if (length >= sizeof(path_environment) - 5) {
        fox_puts("PATH is too long.\n");
        return;
    }
    path_environment[0] = 'P';
    path_environment[1] = 'A';
    path_environment[2] = 'T';
    path_environment[3] = 'H';
    path_environment[4] = '=';
    copy_string(path_environment + 5, value,
                sizeof(path_environment) - 5);
}

__attribute__((noreturn, section(".text.start")))
void _start(void)
{
    char line[128];

    fox_puts("FoxOS C shell. Type help for commands.\n");

    for (;;) {
        long length;
        unsigned long index;

        fox_puts("> ");
        length = fox_read(0, line, sizeof(line) - 1);
        if (length <= 0) {
            fox_puts("read failed\n");
            continue;
        }

        for (index = 0; index < (unsigned long)length; index++) {
            if (line[index] == '\n') {
                break;
            }
        }
        line[index] = '\0';

        if (fox_strcmp(line, "help") == 0) {
            fox_puts("Commands: help about cat <file> ls [dir] stat <path>\n");
            fox_puts("          cd [dir] pwd mkdir <dir> write <path> <text>\n");
            fox_puts("          path [dir:dir] exit\n");
            fox_puts("Run programs by name, e.g. args first second.\n");
            fox_puts("Pipelines: args hello | copy\n");
            fox_puts("Type preempt to test timer scheduling.\n");
        } else if (fox_strcmp(line, "about") == 0) {
            fox_puts("FoxOS shell with initramfs programs and IDE storage.\n");
        } else if (fox_strcmp(line, "exit") == 0) {
            fox_puts("Leaving C shell.\n");
            fox_exit(0);
        } else if (fox_strcmp(line, "ls") == 0) {
            list_directory(".");
        } else if (line[0] == 'l' && line[1] == 's' && line[2] == ' ') {
            list_directory(skip_spaces(&line[3]));
        } else if (fox_strcmp(line, "pwd") == 0) {
            fox_puts(current_directory);
            fox_puts("\n");
        } else if (fox_strcmp(line, "cd") == 0) {
            change_directory("");
        } else if (line[0] == 'c' && line[1] == 'd' && line[2] == ' ') {
            change_directory(skip_spaces(&line[3]));
        } else if (fox_strcmp(line, "path") == 0) {
            fox_puts(path_environment + 5);
            fox_puts("\n");
        } else if (line[0] == 'p' && line[1] == 'a' &&
                   line[2] == 't' && line[3] == 'h' &&
                   line[4] == ' ') {
            set_path(skip_spaces(&line[5]));
        } else if (line[0] == 'e' && line[1] == 'x' &&
                   line[2] == 'p' && line[3] == 'o' &&
                   line[4] == 'r' && line[5] == 't' &&
                   line[6] == ' ') {
            char *assignment = skip_spaces(&line[7]);
            if (assignment[0] == 'p' && assignment[1] == 'a' &&
                assignment[2] == 't' && assignment[3] == 'h' &&
                assignment[4] == '=') {
                set_path(&assignment[5]);
            } else {
                fox_puts("Only path can be exported.\n");
            }
        } else if (line[0] == 's' && line[1] == 't' &&
                   line[2] == 'a' && line[3] == 't' && line[4] == ' ') {
            show_file_status(skip_spaces(&line[5]));
        } else if (line[0] == 'm' && line[1] == 'k' &&
                   line[2] == 'd' && line[3] == 'i' &&
                   line[4] == 'r' && line[5] == ' ') {
            make_directory(skip_spaces(&line[6]));
        } else if (line[0] == 'w' && line[1] == 'r' &&
                   line[2] == 'i' && line[3] == 't' &&
                   line[4] == 'e' && line[5] == ' ') {
            write_file(line);
        } else if (line[0] == 'c' && line[1] == 'a' &&
                   line[2] == 't' &&
                   (line[3] == '\0' || line[3] == ' ')) {
            char *path = skip_spaces(&line[3]);
            if (*path == '\0') {
                fox_puts("Usage: cat <file>\n");
            } else {
                show_file(path);
            }
        } else if (line[0] != '\0') {
            run_command(line);
        }
    }
}
