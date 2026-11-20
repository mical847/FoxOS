; Keyboard-driven command line. Commands are registered in apps/apps.asm.

terminal_screen:
    mov ax, 0x0720
    mov edi, 0xB8000
    mov ecx, 2000
    rep stosw
    cmp byte [graphics_ready], 1
    jne .text_mode

    mov rax, [framebuffer_address]
    mov [terminal_saved_framebuffer], rax
    mov eax, [framebuffer_pitch]
    mov [terminal_saved_pitch], eax
    mov qword [framebuffer_address], TERMINAL_RENDER_BUFFER
    mov dword [framebuffer_pitch], TERMINAL_RENDER_PITCH
    mov byte [terminal_rendering], 1
    call draw_terminal_window
    mov byte [graphics_text_window], 1
    mov ax, 0x7020
    mov edi, 0xB8000
    mov ecx, 80
    rep stosw
    WRITE_TEXT 0x00A0, 0x07, terminal_hint
    WRITE_TEXT 0x0140, 0x0E, last_label
    mov edi, 0x014A
    mov byte [text_attr], 0x07
    mov rsi, last_command
    call write_text
    mov edi, 0x01E0
    mov byte [text_attr], 0x07
    mov rsi, [output_ptr]
    call write_text
    WRITE_TEXT 0x0280, 0x0A, prompt
    mov edi, 0x0289
    mov byte [text_attr], 0x0F
    mov rsi, input_buffer
    call write_text
    mov byte [graphics_text_window], 0
    mov byte [terminal_rendering], 0
    mov rax, [terminal_saved_framebuffer]
    mov [framebuffer_address], rax
    mov eax, [terminal_saved_pitch]
    mov [framebuffer_pitch], eax
    call blit_terminal_window
    ret

.text_mode:
    mov ax, 0x7020
    mov edi, 0xB8000
    mov ecx, 80
    rep stosw
    WRITE_TEXT 0, 0x70, terminal_title
    WRITE_TEXT 0x00A0, 0x07, terminal_hint
    WRITE_TEXT 0x0140, 0x0E, last_label
    mov edi, 0x014A
    mov byte [text_attr], 0x07
    mov rsi, last_command
    call write_text
    mov edi, 0x01E0
    mov byte [text_attr], 0x07
    mov rsi, [output_ptr]
    call write_text
    WRITE_TEXT 0x0280, 0x0A, prompt
    mov edi, 0x0289
    mov byte [text_attr], 0x0F
    mov rsi, input_buffer
    call write_text
    ret

blit_terminal_window:
    push r12
    xor r12d, r12d
.row:
    cmp r12d, TERMINAL_SAVE_HEIGHT
    jae .done
    mov eax, [terminal_window_y]
    add eax, r12d
    sub eax, 2
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, [terminal_window_x]
    sub edx, 2
    shl edx, 1
    add rax, rdx
    mov rdi, rax
    mov eax, r12d
    imul eax, TERMINAL_RENDER_PITCH
    mov esi, TERMINAL_RENDER_BUFFER
    add rsi, rax
    mov ecx, TERMINAL_SAVE_WIDTH
    rep movsw
    inc r12d
    jmp .row
.done:
    pop r12
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

    mov rsi, input_buffer
    mov rdi, last_command
    mov ecx, 40
    rep movsb

    mov r12, app_registry
.find_command:
    mov rsi, [r12]
    test rsi, rsi
    jz .unknown
    mov rdi, input_buffer
    call string_equals
    test al, al
    jnz .run_command
    add r12, 16
    jmp .find_command

.run_command:
    mov rax, [r12 + 8]
    call rax
    jmp .clear_input

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

string_equals:
.next_character:
    mov al, [rdi]
    cmp al, [rsi]
    jne .not_equal
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .next_character
.equal:
    mov al, 1
    ret
.not_equal:
    xor al, al
    ret

system_halt:
    cli
.halt:
    hlt
    jmp .halt

; Set-1 scancodes for lowercase letters, punctuation, and space.
keymap:
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '-', '=', 0, 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0, 0, 'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', 39, '`', 0, 92, 'z', 'x', 'c', 'v'
    db 'b', 'n', 'm', ',', '.', '/', 0, 0, 0, ' ', 0, 0, 0, 0, 0, 0
    times 128 - ($ - keymap) db 0

terminal_title db " FOXOS TERMINAL", 0
terminal_hint db "Type help for commands (lowercase).", 0
last_label db "Last:", 0
prompt db "FoxShell> ", 0
welcome_output db "Welcome.", 0
unknown_output db "Unknown command. Type help.", 0

align 8
output_ptr dq welcome_output
screen_mode db 0
terminal_saved_framebuffer dq 0
terminal_saved_pitch dd 0
input_len db 0
input_buffer times 40 db 0
last_command times 40 db 0

%include "apps/apps.asm"
