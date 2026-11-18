
; FoxOS BIOS bootloader
; NASM, 16-bit real mode
bits 16
org 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    ; Check BIOS INT 13h extensions
    mov ah, 0x41
    mov bx, 0x55AA
    int 0x13
    jc disk_error

    cmp bx, 0xAA55
    jne disk_error

    test cx, 1
    jz disk_error

    ; Load 32 sectors starting at LBA 1
    mov si, disk_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    jmp 0x0800:0x0000

disk_error:
    mov si, error_msg

.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .print

.halt:
    cli
    hlt
    jmp .halt

boot_drive db 0

disk_packet:
    db 0x10
    db 0
    dw 32
    dw 0x0000
    dw 0x0800
    dq 1

error_msg db "FoxOS: BIOS disk error", 0

times 510-($-$$) db 0
dw 0xAA55
