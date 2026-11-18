
NASM = nasm

.PHONY: all run clean

all: build/foxos.img

build:
	mkdir -p build

build/boot.bin: boot/boot.asm | build
	$(NASM) -f bin boot/boot.asm -o build/boot.bin
	test "$$(stat -c%s build/boot.bin)" -eq 512

build/kernel.bin: kernel/kernel.asm | build
	$(NASM) -f bin kernel/kernel.asm -o build/kernel.bin
	test "$$(stat -c%s build/kernel.bin)" -le 16384

build/foxos.img: build/boot.bin build/kernel.bin
	dd if=/dev/zero of=build/foxos.img bs=512 count=2880
	dd if=build/boot.bin of=build/foxos.img conv=notrunc
	dd if=build/kernel.bin of=build/foxos.img bs=512 seek=1 conv=notrunc

run: build/foxos.img
	qemu-system-x86_64 \
		-drive format=raw,file=build/foxos.img,if=ide \
		-m 128M

clean:
	rm -rf build
