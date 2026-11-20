
NASM = nasm
QEMU ?= qemu-system-x86_64
CC ?= gcc
LD ?= ld
OBJCOPY ?= objcopy
PYTHON ?= python3
USER_CFLAGS = -m64 -march=x86-64 -ffreestanding -fno-pic -fno-pie \
	-fno-stack-protector -fno-builtin -fno-asynchronous-unwind-tables \
	-fno-unwind-tables -mno-red-zone -mno-sse -mno-mmx -O2 -Wall -Wextra -Werror
APP_SOURCES := $(wildcard apps/*.asm)
SHELL_SOURCES := $(wildcard shell/*.asm)

.PHONY: all run format clean clear

all: build/foxos.img

build:
	mkdir -p build/userland

build/boot.bin: boot/boot.asm | build
	$(NASM) -f bin boot/boot.asm -o build/boot.bin
	test "$$(stat -c%s build/boot.bin)" -eq 512

build/userland/libc.o: userland/libc.c userland/libc.h | build
	$(CC) $(USER_CFLAGS) -c $< -o $@

build/userland/shell.o: userland/init.c userland/libc.h | build
	$(CC) $(USER_CFLAGS) -c $< -o $@

build/userland/hello.o: userland/hello.c userland/libc.h | build
	$(CC) $(USER_CFLAGS) -c $< -o $@

build/userland/args.o: userland/args.c userland/libc.h | build
	$(CC) $(USER_CFLAGS) -c $< -o $@

build/userland/copy.o: userland/copy.c userland/libc.h | build
	$(CC) $(USER_CFLAGS) -c $< -o $@

build/userland/preempt.o: userland/preempt.c userland/libc.h | build
	$(CC) $(USER_CFLAGS) -c $< -o $@

build/shell.elf: build/userland/shell.o build/userland/libc.o userland/linker.ld
	$(LD) -T userland/linker.ld -o $@ build/userland/shell.o build/userland/libc.o

build/hello.elf: build/userland/hello.o build/userland/libc.o userland/linker.ld
	$(LD) -T userland/linker.ld -o $@ build/userland/hello.o build/userland/libc.o

build/args.elf: build/userland/args.o build/userland/libc.o userland/linker.ld
	$(LD) -T userland/linker.ld -o $@ build/userland/args.o build/userland/libc.o

build/copy.elf: build/userland/copy.o build/userland/libc.o userland/linker.ld
	$(LD) -T userland/linker.ld -o $@ build/userland/copy.o build/userland/libc.o

build/preempt.elf: build/userland/preempt.o build/userland/libc.o userland/linker.ld
	$(LD) -T userland/linker.ld -o $@ build/userland/preempt.o build/userland/libc.o

build/initramfs.bin: tools/mkinitramfs.py build/shell.elf build/hello.elf build/args.elf build/copy.elf build/preempt.elf userland/welcome.txt
	$(PYTHON) tools/mkinitramfs.py $@ shell=build/shell.elf hello=build/hello.elf args=build/args.elf copy=build/copy.elf preempt=build/preempt.elf welcome.txt=userland/welcome.txt
	test "$$(stat -c%s $@)" -eq 49152

build/foxfs.bin: tools/mkfoxfs.py | build
	$(PYTHON) tools/mkfoxfs.py $@
	test "$$(stat -c%s $@)" -eq 5120

build/kernel.bin: kernel/kernel.asm kernel/fs.asm $(SHELL_SOURCES) $(APP_SOURCES) build/initramfs.bin | build
	$(NASM) -f bin kernel/kernel.asm -o build/kernel.bin
	test "$$(stat -c%s build/kernel.bin)" -le 65024

build/foxos.img: build/boot.bin build/kernel.bin build/initramfs.bin build/foxfs.bin
	@if [ ! -e $@ ]; then \
		dd if=/dev/zero of=$@ bs=512 count=2880; \
		dd if=build/foxfs.bin of=$@ bs=512 seek=225 conv=notrunc; \
	fi
	dd if=build/boot.bin of=build/foxos.img conv=notrunc
	dd if=build/kernel.bin of=build/foxos.img bs=512 seek=1 conv=notrunc
	dd if=build/initramfs.bin of=build/foxos.img bs=512 seek=129 conv=notrunc

format: build/foxos.img build/foxfs.bin
	dd if=/dev/zero of=build/foxos.img bs=512 seek=225 count=2655 conv=notrunc
	dd if=build/foxfs.bin of=build/foxos.img bs=512 seek=225 conv=notrunc

run: build/foxos.img
	@if command -v $(QEMU) >/dev/null 2>&1; then \
		$(QEMU) \
			-drive format=raw,file=$(CURDIR)/build/foxos.img,if=ide \
			-m 128M; \
	elif command -v flatpak-spawn >/dev/null 2>&1 && \
		flatpak-spawn --host sh -lc 'command -v $(QEMU) >/dev/null 2>&1'; then \
		flatpak-spawn --host $(QEMU) \
			-drive format=raw,file=$(CURDIR)/build/foxos.img,if=ide \
			-m 128M; \
	else \
		echo "QEMU not found. Install qemu-system-x86 on the host or set QEMU=/path/to/qemu-system-x86_64." >&2; \
		exit 127; \
	fi

clean:
	rm -rf build

clear: clean
