# FoxOS

FoxOS is a small BIOS-booted x86-64 experiment written entirely in NASM
assembly, with a small interactive C shell running in user mode. It starts in
a simple, keyboard-operated desktop and also includes an assembly command
line.

## Build and run

Install NASM, GNU make, GCC, GNU binutils, and QEMU, then run:

```sh
make
make run
```

On Debian or Ubuntu, install QEMU on the host with
`sudo apt install qemu-system-x86`. If VS Code is running as a Flatpak, the
Makefile automatically tries `flatpak-spawn --host` when QEMU is not visible
inside the sandbox. You can also select a different emulator executable with
`make run QEMU=/path/to/qemu-system-x86_64`.

The disk image is `build/foxos.img`. The bootloader reads up to 127 kernel
sectors (1-127) to physical address `0x8000` and a 48 KiB initramfs from
sectors 129-224 to `0x20000`. Sector 128 is left unused. The persistent FoxOS
filesystem uses sectors 225-2879.

The IDE filesystem is separate from the read-only initramfs. It stores up to
128 entries in a root directory and nested directories, with names up to 19
characters. File data uses contiguous extents in the remaining disk sectors
(about 1.29 MiB on the default image). Normal `make` updates the bootloader,
kernel, and initramfs without reformatting an existing image. `make format`
explicitly erases and initializes the writable filesystem; `make clean`
removes the image along with build outputs.
When upgrading an older disk image that has no FoxOS filesystem, run
`make format` once before using the storage commands.

## Controls

- **F1** opens or focuses the graphical terminal window.
- **F2** closes the terminal window and returns focus to the desktop.
- **F3** opens the C shell directly from the desktop.
- Click **Applications** on either panel to open the menu for Terminal, C
  Shell, Shutdown, and About. The welcome window appears only after selecting
  About, and its **X** button closes it.
- Click the terminal title bar to focus and drag the window; click its **X**
  button to close it. The desktop's Applications and Terminal shortcuts open
  the graphical terminal, while its C Shell shortcut launches the C shell.
  Clicking outside the terminal moves focus back to the desktop.
- Terminal commands (lowercase): `help`, `about`, `clear`, `gui`, `reboot`,
  `halt`, `shutdown`, and `cshell` to launch the C shell.

FoxOS switches to VESA mode 0x117 (1024x768, 16-bit color) when the BIOS
supports it, drawing the desktop, windows, buttons, and text directly into the
framebuffer. Its blue wallpaper, dark top and bottom panels, desktop shortcuts,
and welcome window use an XFCE-inspired layout; FoxOS does not include or run
the XFCE desktop environment itself. A PS/2 mouse moves the pointer, activates
shortcuts, and manages the terminal window. Dragging restores only the old
window footprint and redraws the moved window, rather than repainting the full
desktop. Keyboard input goes to the assembly terminal when it is focused. The
C shell retains its existing console behavior.
If VESA setup fails, the desktop falls back to VGA text mode. The PS/2
keyboard uses IRQ1 and a 256-byte scan-code queue shared by the assembly
terminal and user-mode `read`. User programs do not yet have a window-drawing
API.

## Initramfs, ELF programs, and C userland

The read-only `FOXFS001` initramfs has a small root directory and stores
standalone ELF64 executables. `tools/mkinitramfs.py` packages programs built
from `userland/`; the bootloader loads the archive into memory, and the kernel
checks and loads ELF `PT_LOAD` segments into the user address region.
The loader also resolves executables from the writable FoxFS volume, validates
the ELF64 headers and loadable segments, then stages the file from disk before
loading it. A disk path takes precedence over an initramfs filename.

The assembly terminal's `cshell` command launches the C shell. Inside it, type
`hello` to run a separate ELF program, `args first second` to see command-line
arguments and environment, or `args hello | copy` to try a pipeline (type the
pipe character with **Shift+\\**). `help` and
`about` are shell commands; `exit` returns to the assembly terminal. Programs
run at ring 3. The kernel supports up to four processes, each with a private
saved 128 KiB user-memory image that the kernel swaps through the shared
user-memory window; 4 KiB page permissions keep the rest of the 4-6 MiB area
supervisor-only. It supports `fork`, `exec`, `wait`, and `yield`. The PIT
generates timer interrupts at about 100 Hz and preempts processes running in
user mode; timer interrupts received in kernel mode do not switch processes.
Keyboard `read` blocks its process when the queue is empty, allowing other
runnable processes to continue, and wakes it when a key arrives. Type
`preempt` in the shell to verify ticks advance during a busy loop.

The `int 0x80` ABI supports keyboard/file/pipe `read` (0), screen/pipe/file
`write` (1), `open` (2), `close` (3), `stat` (4), `pipe` (22), `yield` (24),
`dup2` (33), `getpid` (39), `fork` (57), program `exec` (59), `exit` (60),
`wait` (61), directory enumeration `readdir` (78), `mkdir` (83), and timer
ticks (96). `open` mode 0 reads files (including initramfs files); mode 1
creates or truncates a writable disk file. Disk paths take precedence over
same-named initramfs files when reading.

The C shell provides `ls [dir]`, `cat <file>`, `cd [dir]`, and `pwd`, plus
`stat <path>`, `mkdir <dir>`, and `write <path> <text>` for the writable
filesystem. Relative paths are resolved from the shell's current directory;
absolute paths and `.`/`..` components are supported. The shell's `PATH`
defaults to `/`, which searches the FoxFS root first and also permits running
root-level initramfs programs by name. Use `path /apps:/` to search another
FoxFS directory before the root; `path` without an argument prints the current
search path. Type the path-list separator `:` with **Shift+;**. The current
path is also passed to child programs in `envp`.
For example:

```text
mkdir notes
cd notes
pwd
write todo.txt remember this
ls
stat todo.txt
cat todo.txt
cd ..
```

`stat` reports type (1 for directory, 2 for file) and byte size; `readdir`
returns one fixed-size entry at a time. `cat welcome.txt` exercises read-only
initramfs access.

To install an ELF into the persistent disk image without rebuilding the
kernel or initramfs, first build the OS, then use the host-side installer:

```sh
make
python3 tools/foxfs_put.py build/foxos.img disk-hello=build/hello.elf
make run
```

Run `disk-hello` from the C shell. The installer can also replace existing
files and install into an existing directory, for example
`apps/disk-hello=build/hello.elf`. It changes only FoxFS data and metadata in
the image; the next normal build preserves those changes.
The `exec` syscall passes `argc`, `argv`, and `envp` at program startup. The
shell passes `FOXOS=FoxOS` and its current `PATH`; `args` displays its arguments
and environment. Commands are split on spaces; quoting and changing variables
other than `PATH` are not supported. The current interface accepts up to 8
arguments and 8 environment strings, with at most 1024 bytes per vector.
`userland/libc.c` and `libc.h` provide a small freestanding C library with
syscall wrappers and basic string/output helpers. It is not a standard C
library yet.

This is an early userland foundation, not a Bash-ready environment. The
initramfs remains read-only; the writable filesystem is a small FoxOS-native
IDE format, not FAT, and does not yet support unlink, rename, permissions, or
full POSIX metadata or crash recovery. There is no mutable shell environment,
signals, or broad POSIX syscall support. There are four 1 KiB in-memory pipes;
their userland read/write wrappers yield and retry when a pipe is temporarily
empty or full. The shell currently supports one pipe between two programs per
command.
GNU Bash has not been built for FoxOS; those interfaces and a more complete C
library are still required.

## Adding a shell app

Shell input is in [shell/shell.asm](shell/shell.asm); individual command
handlers live in [apps/](apps/). Each app is a small NASM file. For example,
copy `apps/about.asm`, then give the new file a unique command name and a
handler that sets `output_ptr`:

```nasm
app_hello_name db "hello", 0

app_hello_run:
    mov rsi, hello_output
    mov [output_ptr], rsi
    ret

hello_output db "Hello from my app!", 0
```

Add `%include "apps/hello.asm"` and `APP_COMMAND hello` to
`apps/apps.asm`. Rebuild with `make`; the Makefile tracks app and shell source
files and rebuilds the kernel when they change. Apps are currently built into
the kernel image, so they are not yet separate files loaded at runtime.

This is a minimal starting point with a basic pixel-graphics desktop and PS/2
mouse, not a Bash-ready environment or FAT-compatible filesystem.