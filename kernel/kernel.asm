; =========================================================
; FoxOS - 64-bit kernel bootstrap, desktop, and command line
; NASM flat binary, loaded at physical address 0x8000
; =========================================================

bits 16
org 0x8000

entry:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Copy the BIOS 8x8 character font before entering long mode.
    push ds
    mov ax, 0x1130
    mov bh, 0x06
    int 0x10
    cld
    mov ax, es
    mov ds, ax
    mov si, bp
    xor ax, ax
    mov es, ax
    mov di, 0x5000
    mov cx, 2048
    rep movsb
    pop ds

    ; Use VGA mode 13h (320x200, 256 colors) for both interfaces.
    mov ax, 0x0013
    int 0x10
    cld

    ; Enable A20.
    in al, 0x92
    or al, 2
    and al, 0xFE
    out 0x92, al

    ; Verify CPUID availability.
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    test eax, 1 << 21
    jz cpu_error

    ; Check extended CPUID support and long mode.
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb cpu_error

    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz cpu_error

    ; Clear page tables.
    mov edi, 0x1000
    xor eax, eax
    mov ecx, 3072
    rep stosd

    ; PML4[0] -> PDPT, PDPT[0] -> page directory.
    mov dword [0x1000], 0x2003
    mov dword [0x2000], 0x3003

    ; Identity-map the first 1 GiB using 2 MiB pages.
    mov edi, 0x3000
    mov eax, 0x83
    mov ecx, 512

.map_pages:
    mov [edi], eax
    mov dword [edi + 4], 0
    add eax, 0x200000
    add edi, 8
    loop .map_pages

    lgdt [gdt_pointer]

    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    mov eax, 0x1000
    mov cr3, eax

    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax

    jmp 0x08:long_mode

cpu_error:
    cli
.error_halt:
    hlt
    jmp .error_halt

align 8
gdt_start:
    dq 0
    dq 0x00AF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:

gdt_pointer:
    dw gdt_end - gdt_start - 1
    dd gdt_start

bits 64
default abs

%macro RECT 5
    mov dword [rect_x], %1
    mov dword [rect_y], %2
    mov dword [rect_w], %3
    mov dword [rect_h], %4
    mov byte [rect_color], %5
    call draw_rect
%endmacro

%macro TEXT 5
    mov dword [text_x], %1
    mov dword [text_y], %2
    mov dword [text_fg], %3
    mov dword [text_bg], %4
    mov rsi, %5
    call draw_string
%endmacro

long_mode:
    cld
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov rsp, 0x90000
    xor rbp, rbp
    mov byte [screen_mode], 0
    call draw_desktop

keyboard_loop:
    in al, 0x64
    test al, 1
    jz keyboard_loop
    in al, 0x60

    ; Ignore key releases and extended scancodes.
    test al, 0x80
    jnz keyboard_loop
    cmp al, 0xE0
    je keyboard_loop

    cmp al, 0x3B
    je .show_terminal
    cmp al, 0x3C
    je .show_desktop
    cmp byte [screen_mode], 1
    jne keyboard_loop
    call terminal_key
    jmp keyboard_loop

.show_terminal:
    mov byte [screen_mode], 1
    call terminal_screen
    jmp keyboard_loop

.show_desktop:
    mov byte [screen_mode], 0
    call draw_desktop
    jmp keyboard_loop

draw_desktop:
    mov byte [fill_color], 1
    call fill_screen

    RECT 0, 0, 320, 18, 9
    TEXT 8, 5, 15, 9, desktop_title

    RECT 10, 34, 300, 118, 7
    RECT 10, 34, 300, 17, 1
    TEXT 18, 39, 15, 1, window_title
    TEXT 22, 66, 0, 7, desktop_welcome
    TEXT 22, 82, 0, 7, desktop_hint
    TEXT 22, 106, 1, 7, desktop_keys

    RECT 0, 184, 320, 16, 8
    RECT 5, 187, 52, 11, 9
    TEXT 10, 189, 15, 9, start_label
    TEXT 68, 189, 15, 8, taskbar_label
    ret

terminal_screen:
    mov byte [fill_color], 0
    call fill_screen
    RECT 0, 0, 320, 18, 1
    TEXT 8, 5, 15, 1, terminal_title
    TEXT 8, 26, 7, 0, terminal_hint
    TEXT 8, 48, 14, 0, last_label
    mov dword [text_x], 56
    mov dword [text_y], 48
    mov dword [text_fg], 7
    mov dword [text_bg], 0
    mov rsi, last_command
    call draw_string
    mov dword [text_x], 8
    mov dword [text_y], 64
    mov dword [text_fg], 15
    mov dword [text_bg], 0
    mov rsi, [output_ptr]
    call draw_string
    TEXT 8, 88, 10, 0, prompt
    mov dword [text_x], 24
    mov dword [text_y], 88
    mov dword [text_fg], 15
    mov dword [text_bg], 0
    mov rsi, input_buffer
    call draw_string
    ret

terminal_key:
    cmp al, 0x1C
    je terminal_submit
    cmp al, 0x0E
    je .backspace

    movzx ebx, al
    cmp ebx, 127
    ja .done
    mov al, [keymap + rbx]
    test al, al
    jz .done
    movzx ebx, byte [input_len]
    cmp ebx, 36
    jae .done
    mov [input_buffer + rbx], al
    inc byte [input_len]
    mov byte [input_buffer + rbx + 1], 0
    call terminal_screen
    ret

.backspace:
    cmp byte [input_len], 0
    je .done
    dec byte [input_len]
    movzx ebx, byte [input_len]
    mov byte [input_buffer + rbx], 0
    call terminal_screen
.done:
    ret

terminal_submit:
    cmp byte [input_buffer], 0
    je .done
    movzx ebx, byte [input_len]
    mov byte [input_buffer + rbx], 0

    ; Keep the most recently executed command visible in the terminal.
    mov rsi, input_buffer
    mov rdi, last_command
    mov ecx, 40
    rep movsb

    cmp dword [input_buffer], 'help'
    jne .check_about
    cmp byte [input_buffer + 4], 0
    jne .unknown
    mov rsi, help_output
    mov [output_ptr], rsi
    jmp .clear_input

.check_about:
    cmp dword [input_buffer], 'abou'
    jne .check_clear
    cmp byte [input_buffer + 4], 't'
    jne .unknown
    cmp byte [input_buffer + 5], 0
    jne .unknown
    mov rsi, about_output
    mov [output_ptr], rsi
    jmp .clear_input

.check_clear:
    cmp dword [input_buffer], 'clea'
    jne .check_gui
    cmp byte [input_buffer + 4], 'r'
    jne .unknown
    cmp byte [input_buffer + 5], 0
    jne .unknown
    mov rsi, empty_output
    mov [output_ptr], rsi
    mov rdi, last_command
    xor eax, eax
    mov ecx, 40
    rep stosb
    jmp .clear_input

.check_gui:
    cmp dword [input_buffer], 'gui'
    jne .check_reboot
    cmp byte [input_buffer + 3], 0
    jne .unknown
    mov byte [screen_mode], 0
    call draw_desktop
    jmp .clear_input

.check_reboot:
    cmp dword [input_buffer], 'rebo'
    jne .check_halt
    cmp word [input_buffer + 4], 'ot'
    jne .unknown
    cmp byte [input_buffer + 6], 0
    jne .unknown
    mov rsi, reboot_output
    mov [output_ptr], rsi
    call terminal_screen
    mov al, 0xFE
    out 0x64, al
    jmp system_halt

.check_halt:
    cmp dword [input_buffer], 'halt'
    jne .unknown
    cmp byte [input_buffer + 4], 0
    jne .unknown
    mov rsi, halt_output
    mov [output_ptr], rsi
    call terminal_screen
    jmp system_halt

.unknown:
    mov rsi, unknown_output
    mov [output_ptr], rsi

.clear_input:
    mov byte [input_len], 0
    mov byte [input_buffer], 0
    cmp byte [screen_mode], 1
    jne .done
    call terminal_screen
.done:
    ret

system_halt:
    cli
    hlt
    jmp system_halt

fill_screen:
    mov al, [fill_color]
    mov edi, 0xA0000
    mov ecx, 64000
    rep stosb
    ret

draw_rect:
    mov eax, [rect_y]
    imul eax, eax, 320
    add eax, [rect_x]
    add eax, 0xA0000
    mov edi, eax
    mov ebx, [rect_h]
    test ebx, ebx
    jz .done
.row:
    mov al, [rect_color]
    mov ecx, [rect_w]
    rep stosb
    mov eax, 320
    sub eax, [rect_w]
    add rdi, rax
    dec ebx
    jnz .row
.done:
    ret

draw_string:
    mov [text_ptr], rsi
.next_char:
    mov rsi, [text_ptr]
    lodsb
    mov [text_ptr], rsi
    test al, al
    jz .done
    mov [char_value], al
    call draw_char
    add dword [text_x], 8
    jmp .next_char
.done:
    ret

draw_char:
    movzx eax, byte [char_value]
    shl eax, 3
    add eax, 0x5000
    mov esi, eax

    mov eax, [text_y]
    imul eax, eax, 320
    add eax, [text_x]
    add eax, 0xA0000
    mov edi, eax

    mov edx, [text_fg]
    mov r10d, [text_bg]
    mov r8d, 8
.glyph_row:
    mov al, [rsi]
    mov ecx, 8
.glyph_pixel:
    test al, 0x80
    jz .background_pixel
    mov [rdi], dl
    jmp .next_pixel
.background_pixel:
    mov [rdi], r10b
.next_pixel:
    shl al, 1
    inc rdi
    dec ecx
    jnz .glyph_pixel
    add rdi, 312
    inc rsi
    dec r8d
    jnz .glyph_row
    ret

; BIOS keyboard set-1 scancode-to-ASCII map (lowercase shell commands).
keymap:
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 0, 0, 0, 0, 'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', 0, 0, 0, 0, 0, 'z', 'x', 'c', 'v'
    db 'b', 'n', 'm', 0, 0, 0, 0, 0, 0, ' ', 0, 0, 0, 0, 0, 0
    times 128 - ($ - keymap) db 0

desktop_title db "FOXOS DESKTOP", 0
window_title db "WELCOME TO FOXOS", 0
desktop_welcome db "FOXOS 64-BIT ASSEMBLY SYSTEM", 0
desktop_hint db "A tiny desktop and command line.", 0
desktop_keys db "F1: terminal       F2: desktop", 0
start_label db "FOXOS", 0
taskbar_label db "F1 TERMINAL  |  F2 DESKTOP", 0
terminal_title db "FOXOS TERMINAL", 0
terminal_hint db "Type help for commands (lowercase).", 0
last_label db "Last:", 0
prompt db "> ", 0

welcome_output db "Welcome. Type help to see commands.", 0
help_output db "help about clear gui reboot halt", 0
about_output db "FoxOS: NASM-only 64-bit assembly OS.", 0
unknown_output db "Unknown command. Type help.", 0
reboot_output db "Rebooting...", 0
halt_output db "System halted.", 0
empty_output db 0

align 8
text_ptr dq 0
output_ptr dq welcome_output
rect_x dd 0
rect_y dd 0
rect_w dd 0
rect_h dd 0
text_x dd 0
text_y dd 0
text_fg dd 0
text_bg dd 0
fill_color db 0
rect_color db 0
screen_mode db 0
input_len db 0
char_value db 0
input_buffer times 40 db 0
last_command times 40 db 0
