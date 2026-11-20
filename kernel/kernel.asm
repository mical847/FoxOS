; FoxOS - 64-bit kernel with a VBE desktop and shell
; NASM flat binary, loaded at physical address 0x8000

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

    ; Capture the BIOS 8x16 font before entering VBE graphics mode.
    mov ax, 0x0003
    int 0x10
    mov ax, 0x1130
    mov bh, 6
    int 0x10
    push ds
    push es
    mov ax, es
    mov ds, ax
    mov si, bp
    mov ax, 0x5000
    mov es, ax
    xor di, di
    mov cx, 4096
    rep movsb
    pop es
    pop ds
    call setup_vbe_mode

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
    mov dword [0x1000], 0x2007
    mov dword [0x2000], 0x3007

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
    cmp byte [0x60FF], 1
    jne .no_framebuffer_mapping
    mov eax, [0x6028]
    and eax, 0xFFE00000
    or eax, 0x83
    mov [0x3FC0], eax
    mov dword [0x3FC4], 0
.no_framebuffer_mapping:
    ; The kernel narrows user access to 4-4.125 MiB using 4 KiB pages.
    mov dword [0x3010], 0x400087

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

setup_vbe_mode:
    push es
    mov byte [0x60FF], 0
    mov ax, 0x0600
    mov es, ax
    xor di, di
    mov ax, 0x4F01
    mov cx, 0x0117
    int 0x10
    cmp ax, 0x004F
    jne .done
    cmp word [es:di + 18], 1024
    jne .done
    cmp word [es:di + 20], 768
    jne .done
    cmp byte [es:di + 25], 16
    jne .done
    cmp byte [es:di + 27], 6
    jne .done
    cmp dword [es:di + 40], 0
    je .done
    mov ax, 0x4F02
    mov bx, 0x4117
    int 0x10
    cmp ax, 0x004F
    jne .done
    mov byte [0x60FF], 1
.done:
    pop es
    ret

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
    dq 0x00AFFA000000FFFF
    dq 0x00CFF2000000FFFF
    dw 103
    dw 0
    db 0
    db 0x89
    db 0
    db 0
    dd 0
    dd 0
tss_descriptor equ gdt_start + 5 * 8
gdt_end:

gdt_pointer:
    dw gdt_end - gdt_start - 1
    dd gdt_start

bits 64
default abs

%define PROCESS_COUNT 4
%define PROCESS_SIZE 80
%define PROCESS_STACK_BASE 0x180000
%define FD_COUNT 11
%define FD_ENTRY_SIZE 32
%define PIPE_COUNT 4
%define PIPE_SIZE 1072
%define FRAMEBUFFER_VIRTUAL 0x3F000000
%define FONT_PHYSICAL 0x50000
%define TERMINAL_WINDOW_WIDTH 704
%define TERMINAL_WINDOW_HEIGHT 500
%define TERMINAL_SAVE_WIDTH (TERMINAL_WINDOW_WIDTH + 4)
%define TERMINAL_SAVE_HEIGHT (TERMINAL_WINDOW_HEIGHT + 4)
%define TERMINAL_SAVE_BUFFER 0x500000
%define TERMINAL_RENDER_BUFFER 0x600000
%define TERMINAL_RENDER_PITCH (TERMINAL_SAVE_WIDTH * 2)
%define FS_ENTRY_COUNT 128
%define FS_ENTRY_SIZE 32
%define FS_HEADER_SECTOR 225
%define FS_DATA_START 235
%define FS_DATA_SECTORS 2645

%macro WRITE_TEXT 3
    mov edi, %1
    mov byte [text_attr], %2
    mov rsi, %3
    call write_text
%endmacro

%macro FILL_RECT 5
    mov edi, %1
    mov esi, %2
    mov edx, %3
    mov ecx, %4
    mov r8d, %5
    call fill_rect
%endmacro

%macro DRAW_TEXT 5
    mov edi, %1
    mov esi, %2
    mov edx, %3
    mov r8d, %4
    mov rcx, %5
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
    call setup_user_pages
    call setup_framebuffer
    mov rax, tss
    mov word [tss_descriptor + 2], ax
    shr rax, 16
    mov byte [tss_descriptor + 4], al
    shr rax, 8
    mov byte [tss_descriptor + 7], al
    shr rax, 8
    mov dword [tss_descriptor + 8], eax
    mov qword [tss + 4], 0x90000
    mov word [tss + 102], 104
    mov ax, 0x28
    ltr ax
    call setup_syscall_gate
    call setup_timer
    call setup_mouse
    call fs_mount

    mov byte [screen_mode], 0
    mov dword [mouse_x], 512
    mov dword [mouse_y], 384
    call draw_desktop
    call draw_mouse_cursor
    jmp user_program_finished

setup_user_pages:
    mov dword [0x3010], 0x4007
    mov edi, 0x4000
    mov eax, 0x400007
    mov ecx, 32
.user_pages:
    mov [rdi], eax
    mov dword [rdi + 4], 0
    add eax, 0x1000
    add rdi, 8
    loop .user_pages

    mov eax, 0x420003
    mov ecx, 480
.kernel_pages:
    mov [rdi], eax
    mov dword [rdi + 4], 0
    add eax, 0x1000
    add rdi, 8
    loop .kernel_pages

    mov rax, cr3
    mov cr3, rax
    ret

user_program_finished:
    mov rsp, 0x90000
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov byte [process_kind], 0
    cmp byte [screen_mode], 1
    jne .show_desktop
    cmp byte [graphics_ready], 1
    jne .show_text_terminal
    call draw_desktop
    call draw_mouse_cursor
    jmp keyboard_loop
.show_text_terminal:
    call terminal_screen
    jmp keyboard_loop
.show_desktop:
    call draw_desktop
    call draw_mouse_cursor
    jmp keyboard_loop

keyboard_loop:
    cmp byte [graphics_ready], 1
    jne .wait_for_key
    cmp byte [mouse_event], 0
    je .wait_for_key
    mov byte [mouse_event], 0
    cmp byte [terminal_drag], 0
    je .draw_mouse
    test byte [mouse_buttons], 1
    jz .end_terminal_drag
    call erase_mouse_cursor
    call drag_terminal_window
    call draw_mouse_cursor
    jmp .mouse_event_done
.end_terminal_drag:
    mov byte [terminal_drag], 0
.draw_mouse:
    call draw_mouse_cursor
.mouse_click:
    cmp byte [mouse_click], 0
    je .mouse_event_done
    mov byte [mouse_click], 0
    call dispatch_mouse_click
.mouse_event_done:
    call draw_mouse_cursor
    jmp keyboard_loop
.wait_for_key:
    mov eax, [keyboard_head]
    cmp eax, [keyboard_tail]
    jne .key_available
    sti
    hlt
    jmp keyboard_loop
.key_available:
    mov ebx, [keyboard_tail]
    mov eax, ebx
    and eax, 255
    movzx eax, byte [keyboard_buffer + rax]
    inc ebx
    mov [keyboard_tail], ebx

    cmp al, 0x2A
    je .shift_down
    cmp al, 0x36
    je .shift_down
    test al, 0x80
    jnz .key_release
    cmp al, 0xE0
    je keyboard_loop

    cmp al, 0x3B
    je .show_terminal
    cmp al, 0x3C
    je .show_desktop
    cmp al, 0x3D
    je .launch_c_shell
    cmp byte [screen_mode], 1
    jne keyboard_loop
    cmp byte [graphics_ready], 1
    jne .terminal_key
    push rax
    call erase_mouse_cursor
    pop rax
.terminal_key:
    call terminal_key
    cmp byte [graphics_ready], 1
    jne keyboard_loop
    call draw_mouse_cursor
    jmp keyboard_loop

.shift_down:
    mov byte [shift_down], 1
    jmp keyboard_loop
.key_release:
    and al, 0x7F
    cmp al, 0x2A
    je .shift_up
    cmp al, 0x36
    je .shift_up
    jmp keyboard_loop
.shift_up:
    mov byte [shift_down], 0
    jmp keyboard_loop

.show_terminal:
    mov byte [applications_menu_open], 0
    mov byte [screen_mode], 1
    cmp byte [graphics_ready], 1
    jne .show_text_terminal
    mov byte [terminal_visible], 1
    mov byte [terminal_drag], 0
    call draw_desktop
    call draw_mouse_cursor
    jmp keyboard_loop
.show_text_terminal:
    call terminal_screen
    jmp keyboard_loop

.show_desktop:
    mov byte [applications_menu_open], 0
    mov byte [screen_mode], 0
    mov byte [terminal_visible], 0
    mov byte [terminal_drag], 0
    call draw_desktop
    call draw_mouse_cursor
    jmp keyboard_loop
.launch_c_shell:
    cmp byte [screen_mode], 0
    jne keyboard_loop
    mov byte [applications_menu_open], 0
    call launch_c_shell
    jmp keyboard_loop

setup_syscall_gate:
    mov rax, syscall_entry
    mov word [idt + 0x80 * 16], ax
    mov word [idt + 0x80 * 16 + 2], 0x08
    mov byte [idt + 0x80 * 16 + 4], 0
    mov byte [idt + 0x80 * 16 + 5], 0xEE
    shr rax, 16
    mov word [idt + 0x80 * 16 + 6], ax
    shr rax, 16
    mov dword [idt + 0x80 * 16 + 8], eax
    mov dword [idt + 0x80 * 16 + 12], 0
    lidt [idt_pointer]
    ret

setup_timer:
    mov rax, timer_irq
    mov word [idt + 32 * 16], ax
    mov word [idt + 32 * 16 + 2], 0x08
    mov byte [idt + 32 * 16 + 4], 0
    mov byte [idt + 32 * 16 + 5], 0x8E
    shr rax, 16
    mov word [idt + 32 * 16 + 6], ax
    shr rax, 16
    mov dword [idt + 32 * 16 + 8], eax
    mov dword [idt + 32 * 16 + 12], 0

    mov rax, keyboard_irq
    mov word [idt + 33 * 16], ax
    mov word [idt + 33 * 16 + 2], 0x08
    mov byte [idt + 33 * 16 + 4], 0
    mov byte [idt + 33 * 16 + 5], 0x8E
    shr rax, 16
    mov word [idt + 33 * 16 + 6], ax
    shr rax, 16
    mov dword [idt + 33 * 16 + 8], eax
    mov dword [idt + 33 * 16 + 12], 0

    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFC
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    mov al, 0x36
    out 0x43, al
    mov ax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al
    ret

setup_mouse:
    push rbx
    cmp byte [graphics_ready], 1
    jne .done
    mov ecx, 0x10000
.wait_input:
    in al, 0x64
    test al, 2
    jz .enable_aux
    loop .wait_input
    jmp .done
.enable_aux:
    mov al, 0xA8
    out 0x64, al
    mov ecx, 0x10000
.wait_read_command:
    in al, 0x64
    test al, 2
    jz .read_command
    loop .wait_read_command
    jmp .done
.read_command:
    mov al, 0x20
    out 0x64, al
    mov ecx, 0x10000
.wait_command_byte:
    in al, 0x64
    test al, 1
    jnz .get_command_byte
    loop .wait_command_byte
    jmp .done
.get_command_byte:
    in al, 0x60
    or al, 2
    and al, 0xDF
    mov bl, al
    mov ecx, 0x10000
.wait_write_command:
    in al, 0x64
    test al, 2
    jz .write_command
    loop .wait_write_command
    jmp .done
.write_command:
    mov al, 0x60
    out 0x64, al
    mov ecx, 0x10000
.wait_command_data:
    in al, 0x64
    test al, 2
    jz .send_command_data
    loop .wait_command_data
    jmp .done
.send_command_data:
    mov al, bl
    out 0x60, al
    mov ecx, 0x10000
.wait_mouse_prefix:
    in al, 0x64
    test al, 2
    jz .send_mouse_prefix
    loop .wait_mouse_prefix
    jmp .done
.send_mouse_prefix:
    mov al, 0xD4
    out 0x64, al
    mov ecx, 0x10000
.wait_mouse_command:
    in al, 0x64
    test al, 2
    jz .send_mouse_command
    loop .wait_mouse_command
    jmp .done
.send_mouse_command:
    mov al, 0xF4
    out 0x60, al
    mov ecx, 0x10000
.wait_mouse_ack:
    in al, 0x64
    test al, 1
    jnz .check_mouse_ack
    loop .wait_mouse_ack
    jmp .done
.check_mouse_ack:
    in al, 0x60
    cmp al, 0xFA
    jne .done
    mov rax, mouse_irq
    mov word [idt + 44 * 16], ax
    mov word [idt + 44 * 16 + 2], 0x08
    mov byte [idt + 44 * 16 + 4], 0
    mov byte [idt + 44 * 16 + 5], 0x8E
    shr rax, 16
    mov word [idt + 44 * 16 + 6], ax
    shr rax, 16
    mov dword [idt + 44 * 16 + 8], eax
    mov dword [idt + 44 * 16 + 12], 0
    mov al, 0xF8
    out 0x21, al
    mov al, 0xEF
    out 0xA1, al
.done:
    pop rbx
    ret

keyboard_irq:
    cld
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    in al, 0x60
    movzx ebx, al
    mov eax, [keyboard_head]
    mov ecx, eax
    sub ecx, [keyboard_tail]
    cmp ecx, 256
    jae .acknowledge
    mov ecx, eax
    and ecx, 255
    mov [keyboard_buffer + rcx], bl
    inc eax
    mov [keyboard_head], eax

    xor ecx, ecx
.wake_reader:
    cmp ecx, PROCESS_COUNT
    jae .acknowledge
    mov rdx, rcx
    imul rdx, rdx, PROCESS_SIZE
    cmp qword [process_table + rdx], 4
    jne .next_reader
    mov qword [process_table + rdx], 1
    jmp .acknowledge
.next_reader:
    inc ecx
    jmp .wake_reader

.acknowledge:
    mov al, 0x20
    out 0x20, al
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

mouse_irq:
    cld
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    in al, 0x60
    movzx ebx, byte [mouse_packet_index]
    cmp ebx, 0
    jne .packet_data
    test al, 8
    jz .acknowledge
.packet_data:
    mov [mouse_packet + rbx], al
    inc ebx
    cmp ebx, 3
    jb .save_index
    mov byte [mouse_packet_index], 0
    mov al, [mouse_packet]
    mov bl, al
    test al, 0x40
    jnz .vertical_delta
    movsx eax, byte [mouse_packet + 1]
    add [mouse_x], eax
    cmp dword [mouse_x], 0
    jge .clamp_x_high
    mov dword [mouse_x], 0
    jmp .vertical_delta
.clamp_x_high:
    cmp dword [mouse_x], 1016
    jle .vertical_delta
    mov dword [mouse_x], 1016
.vertical_delta:
    test bl, 0x80
    jnz .update_buttons
    movsx eax, byte [mouse_packet + 2]
    sub [mouse_y], eax
    cmp dword [mouse_y], 0
    jge .clamp_y_high
    mov dword [mouse_y], 0
    jmp .update_buttons
.clamp_y_high:
    cmp dword [mouse_y], 756
    jle .update_buttons
    mov dword [mouse_y], 756
.update_buttons:
    mov al, bl
    and al, 7
    mov cl, [mouse_buttons]
    test al, 1
    jz .store_buttons
    test cl, 1
    jnz .store_buttons
    mov byte [mouse_click], 1
.store_buttons:
    mov [mouse_buttons], al
    mov byte [mouse_event], 1
    jmp .acknowledge
.save_index:
    mov [mouse_packet_index], bl
.acknowledge:
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

timer_irq:
    cld
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    inc qword [timer_ticks]
    mov al, 0x20
    out 0x20, al

    test byte [rsp + 128], 3
    jz .return
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov [process_table + rbx + 24], rsp
    mov qword [process_table + rbx + 48], 1
    call schedule_process
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

enter_user_mode:
    mov ax, 0x23
    mov ds, ax
    mov es, ax
    push qword 0x23
    push qword 0x41FFE0
    pushfq
    or qword [rsp], 1 << 9
    push qword 0x1B
    push qword [user_entry]
    iretq

launch_c_shell:
    mov ax, 0x0720
    mov edi, 0xB8000
    mov ecx, 2000
    rep stosw
    mov qword [user_cursor], 0
    cmp byte [graphics_ready], 1
    jne .load_shell
    call clear_framebuffer
    FILL_RECT 0, 0, 1024, 36, 0x2104
    DRAW_TEXT 14, 10, 0xFFFF, 0x2104, shell_window_title
    mov byte [text_attr], 0x0F
    mov qword [user_cursor], 240
.load_shell:
    mov rsi, shell_name
    call load_elf
    jc system_halt
    mov rdi, process_table
    xor eax, eax
    mov ecx, PROCESS_COUNT * PROCESS_SIZE / 8
    rep stosq
    mov rdi, fd_table
    xor eax, eax
    mov ecx, PROCESS_COUNT * FD_COUNT * FD_ENTRY_SIZE / 8
    rep stosq
    mov rdi, pipe_table
    mov ecx, PIPE_COUNT * PIPE_SIZE / 8
    rep stosq
    mov qword [process_table], 1
    mov qword [process_table + 8], 1
    mov qword [process_table + 16], 0
    mov qword [next_process_id], 2
    mov dword [current_process], 0
    mov qword [tss + 4], PROCESS_STACK_BASE + 0x4000
    mov byte [process_kind], 1
    jmp enter_user_mode

syscall_entry:
    cld
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    cmp rax, 1
    je .write
    cmp rax, 0
    je .read
    cmp rax, 2
    je .open
    cmp rax, 3
    je .close
    cmp rax, 22
    je .pipe
    cmp rax, 33
    je .dup2
    cmp rax, 39
    je .getpid
    cmp rax, 57
    je .fork
    cmp rax, 59
    je .exec
    cmp rax, 60
    je .exit
    cmp rax, 61
    je .wait
    cmp rax, 96
    je .ticks
    cmp rax, 24
    je .yield
    cmp rax, 4
    je .stat
    cmp rax, 78
    je .readdir
    cmp rax, 83
    je .mkdir
    mov rax, -38
    jmp .return

.write:
    mov rax, rsi
    cmp rax, 0x400000
    jb .bad_pointer
    add rax, rdx
    jc .bad_pointer
    cmp rax, 0x420000
    ja .bad_pointer
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    mov rax, [rsp + 72]
    cmp rax, FD_COUNT
    jae .bad_descriptor
    imul rax, rax, FD_ENTRY_SIZE
    mov ebx, [current_process]
    imul rbx, rbx, FD_COUNT * FD_ENTRY_SIZE
    lea r15, [fd_table + rbx + rax]
    cmp qword [r15], 0
    je .write_console
    cmp qword [r15], 5
    je .write_disk_file
    cmp qword [r15], 3
    jne .bad_descriptor
    mov rax, [r15 + 8]
    cmp rax, PIPE_COUNT
    jae .bad_descriptor
    imul rax, rax, PIPE_SIZE
    lea r15, [pipe_table + rax]
.write_pipe:
    test r13, r13
    jz .write_done
    cmp qword [r15 + 8], 0
    je .pipe_broken
    cmp qword [r15 + 40], 1024
    jae .pipe_full
    mov rax, [r15 + 32]
    mov bl, [r12]
    mov [r15 + rax + 48], bl
    inc rax
    and eax, 1023
    mov [r15 + 32], rax
    inc qword [r15 + 40]
    inc r12
    dec r13
    inc r14
    jmp .write_pipe
.pipe_full:
    test r14, r14
    jnz .write_done
    mov rax, -11
    jmp .return
.pipe_broken:
    test r14, r14
    jnz .write_done
    mov rax, -32
    jmp .return
.write_console:
    cmp qword [rsp + 72], 1
    je .write_next
    cmp qword [rsp + 72], 2
    jne .bad_descriptor
.write_next:
    test r13, r13
    jz .write_done
    mov al, [r12]
    inc r12
    dec r13
    inc r14
    call console_putc
    jmp .write_next
.write_done:
    mov rax, r14
    jmp .return

.write_disk_file:
    cmp qword [r15 + 16], 0
    je .bad_descriptor
    mov rdi, [r15 + 8]
    call fs_entry_from_id
    test rax, rax
    jz .bad_descriptor
    mov rdx, rax
    mov rsi, r15
    mov rdi, r12
    mov rcx, r13
    call fs_write_file
    jmp .return

.open:
    mov r14, [rsp + 80]
    cmp r14, 1
    ja .bad_descriptor
    mov [fs_open_flags], r14
    mov rdi, [rsp + 72]
    cmp rdi, 0x400000
    jb .bad_pointer
    cmp rdi, 0x420000
    jae .bad_pointer
    call fs_resolve
    jnc .open_disk_entry
    test r14, r14
    jz .open_initramfs
    mov al, 2
    call fs_create_entry
    jc .open_storage_error
    mov rdi, rax
    call fs_entry_id
    mov r13, rax
    mov qword [fs_open_kind], 5
    jmp .open_allocate_fd
.open_initramfs:
    cmp byte [fs_missing_final], 1
    jne .no_entry
    mov rdi, [rsp + 72]
    call find_file
    jc .no_entry
    mov r13, rax
    mov [fs_open_size], rdx
    mov qword [fs_open_kind], 1
    jmp .open_allocate_fd
.open_disk_entry:
    test rax, rax
    jz .open_root_path
    test r14, r14
    jz .open_existing_read
    cmp byte [rax + 20], 2
    jne .open_is_directory
    mov r13, rax
    mov rdi, r13
    call fs_truncate_file
    jc .open_storage_error
    mov rdi, r13
    call fs_entry_id
    mov r13, rax
    mov qword [fs_open_kind], 5
    jmp .open_allocate_fd
.open_existing_read:
    test rax, rax
    jz .open_root_directory
    cmp byte [rax + 20], 1
    je .open_directory
    cmp byte [rax + 20], 2
    jne .no_entry
.open_disk_file:
    mov rdi, rax
    call fs_entry_id
    mov r13, rax
    mov qword [fs_open_kind], 5
    jmp .open_allocate_fd
.open_directory:
    mov rdi, rax
    call fs_entry_id
    mov r13, rax
    mov qword [fs_open_kind], 6
    jmp .open_allocate_fd
.open_root_directory:
    xor r13d, r13d
    mov qword [fs_open_kind], 6
    jmp .open_allocate_fd
.open_root_path:
    test r14, r14
    jnz .open_root_write
    jmp .open_root_directory
.open_root_write:
    mov rax, -21
    jmp .return
.open_is_directory:
    cmp byte [rax + 20], 1
    je .open_root_write
    jmp .no_entry
.open_storage_error:
    mov rax, -5
    jmp .return
.open_allocate_fd:
    mov eax, [current_process]
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    lea r12, [fd_table + rax + 3 * FD_ENTRY_SIZE]
    mov ebx, 3
.open_slot:
    cmp qword [r12], 0
    je .open_found
    add r12, FD_ENTRY_SIZE
    inc ebx
    cmp ebx, 11
    jb .open_slot
    mov rax, -24
    jmp .return
.open_found:
    mov rax, [fs_open_kind]
    mov [r12], rax
    mov [r12 + 8], r13
    mov qword [r12 + 16], 0
    cmp rax, 1
    jne .open_not_initramfs
    mov rdx, [fs_open_size]
    mov [r12 + 16], rdx
    jmp .open_fd_ready
.open_not_initramfs:
    cmp rax, 5
    jne .open_fd_ready
    mov rdx, [fs_open_flags]
    mov [r12 + 16], rdx
.open_fd_ready:
    mov qword [r12 + 24], 0
    mov eax, ebx
    jmp .return

.close:
    mov rax, [rsp + 72]
    cmp rax, FD_COUNT
    jae .bad_descriptor
    imul rax, rax, FD_ENTRY_SIZE
    mov ebx, [current_process]
    imul rbx, rbx, FD_COUNT * FD_ENTRY_SIZE
    lea r12, [fd_table + rbx + rax]
    cmp qword [r12], 4
    je .bad_descriptor
    cmp qword [r12], 0
    je .close_standard
    mov rdi, r12
    call release_fd_entry
    xor eax, eax
    jmp .return
.close_standard:
    cmp qword [rsp + 72], 3
    jae .bad_descriptor
    mov qword [r12], 4
    xor eax, eax
    jmp .return

.pipe:
    mov rdi, [rsp + 72]
    cmp rdi, 0x400000
    jb .bad_pointer
    cmp rdi, 0x420000 - 8
    ja .bad_pointer
    mov r12, rdi
    mov eax, [current_process]
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    lea r13, [fd_table + rax + 3 * FD_ENTRY_SIZE]
    mov ebx, 3
    mov r14d, -1
    mov r15d, -1
.pipe_fd_scan:
    cmp qword [r13], 0
    je .pipe_fd_free
    cmp qword [r13], 4
    je .pipe_fd_free
    jmp .pipe_fd_next
.pipe_fd_free:
    cmp r14d, -1
    jne .pipe_second_fd
    mov r14d, ebx
    jmp .pipe_fd_next
.pipe_second_fd:
    mov r15d, ebx
    jmp .pipe_fds_ready
.pipe_fd_next:
    add r13, FD_ENTRY_SIZE
    inc ebx
    cmp ebx, FD_COUNT
    jb .pipe_fd_scan
    mov rax, -24
    jmp .return
.pipe_fds_ready:
    xor ebx, ebx
    mov r13, pipe_table
.pipe_slot_scan:
    cmp qword [r13], 0
    je .pipe_slot_found
    add r13, PIPE_SIZE
    inc ebx
    cmp ebx, PIPE_COUNT
    jb .pipe_slot_scan
    mov rax, -24
    jmp .return
.pipe_slot_found:
    mov qword [r13], 1
    mov qword [r13 + 8], 1
    mov qword [r13 + 16], 1
    mov qword [r13 + 24], 0
    mov qword [r13 + 32], 0
    mov qword [r13 + 40], 0
    mov eax, [current_process]
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    mov rdx, r14
    shl rdx, 5
    lea rdi, [fd_table + rax + rdx]
    mov qword [rdi], 2
    mov [rdi + 8], rbx
    mov rdx, r15
    shl rdx, 5
    lea rdi, [fd_table + rax + rdx]
    mov qword [rdi], 3
    mov [rdi + 8], rbx
    mov [r12], r14d
    mov [r12 + 4], r15d
    xor eax, eax
    jmp .return

.dup2:
    mov rax, [rsp + 72]
    cmp rax, FD_COUNT
    jae .bad_descriptor
    mov rdx, [rsp + 80]
    cmp rdx, FD_COUNT
    jae .bad_descriptor
    cmp rax, rdx
    je .dup_same
    mov ebx, [current_process]
    imul rbx, rbx, FD_COUNT * FD_ENTRY_SIZE
    imul rax, rax, FD_ENTRY_SIZE
    imul rdx, rdx, FD_ENTRY_SIZE
    lea r13, [fd_table + rbx + rax]
    lea r12, [fd_table + rbx + rdx]
    cmp qword [r13], 4
    je .bad_descriptor
    cmp qword [r12], 0
    je .dup_copy
    cmp qword [r12], 4
    je .dup_copy
    mov rdi, r12
    call release_fd_entry
.dup_copy:
    mov rsi, r13
    mov rdi, r12
    mov ecx, FD_ENTRY_SIZE / 8
    rep movsq
    cmp qword [r12], 2
    je .dup_reader
    cmp qword [r12], 3
    je .dup_writer
    mov rax, [rsp + 80]
    jmp .return
.dup_reader:
    mov rax, [r12 + 8]
    imul rax, rax, PIPE_SIZE
    inc qword [pipe_table + rax + 8]
    mov rax, [rsp + 80]
    jmp .return
.dup_writer:
    mov rax, [r12 + 8]
    imul rax, rax, PIPE_SIZE
    inc qword [pipe_table + rax + 16]
    mov rax, [rsp + 80]
    jmp .return
.dup_same:
    mov rax, [rsp + 72]
    jmp .return

.getpid:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov rax, [process_table + rbx + 8]
    jmp .return

.ticks:
    mov rax, [timer_ticks]
    jmp .return

.stat:
    cmp byte [fs_ready], 0
    je .storage_unavailable
    mov rdi, [rsp + 72]
    cmp rdi, 0x400000
    jb .bad_pointer
    cmp rdi, 0x420000
    jae .bad_pointer
    mov rax, [rsp + 80]
    cmp rax, 0x400000
    jb .bad_pointer
    add rax, 16
    jc .bad_pointer
    cmp rax, 0x420000
    ja .bad_pointer
    mov rax, [rsp + 80]
    mov [fs_stat_buffer], rax
    mov rdi, [rsp + 72]
    call fs_resolve
    jc .stat_initramfs
    mov rdi, [fs_stat_buffer]
    test rax, rax
    jz .stat_root
    movzx edx, byte [rax + 20]
    mov [rdi], rdx
    mov edx, [rax + 25]
    mov [rdi + 8], rdx
    xor eax, eax
    jmp .return
.stat_root:
    mov qword [rdi], 1
    mov qword [rdi + 8], 0
    xor eax, eax
    jmp .return
.stat_initramfs:
    cmp byte [fs_missing_final], 1
    jne .no_entry
    mov rdi, [rsp + 72]
    call find_file
    jc .no_entry
    mov rdi, [fs_stat_buffer]
    mov qword [rdi], 2
    mov [rdi + 8], rdx
    xor eax, eax
    jmp .return

.mkdir:
    cmp byte [fs_ready], 0
    je .storage_unavailable
    mov rdi, [rsp + 72]
    cmp rdi, 0x400000
    jb .bad_pointer
    cmp rdi, 0x420000
    jae .bad_pointer
    call fs_resolve
    jnc .already_exists
    cmp byte [fs_missing_final], 0
    je .no_entry
    mov al, 1
    call fs_create_entry
    jc .storage_full
    xor eax, eax
    jmp .return
.already_exists:
    mov rax, -17
    jmp .return
.storage_full:
    mov rax, -28
    jmp .return
.storage_unavailable:
    mov rax, -5
    jmp .return

.readdir:
    cmp byte [fs_ready], 0
    je .storage_unavailable
    mov rax, [rsp + 72]
    cmp rax, FD_COUNT
    jae .bad_descriptor
    imul rax, rax, FD_ENTRY_SIZE
    mov ebx, [current_process]
    imul rbx, rbx, FD_COUNT * FD_ENTRY_SIZE
    lea r12, [fd_table + rbx + rax]
    cmp qword [r12], 6
    jne .bad_descriptor
    cmp qword [rsp + 88], 32
    jb .bad_pointer
    mov r13, [rsp + 80]
    cmp r13, 0x400000
    jb .bad_pointer
    mov rax, r13
    add rax, 32
    jc .bad_pointer
    cmp rax, 0x420000
    ja .bad_pointer
    mov r14, [r12 + 8]
.readdir_next:
    mov r15, [r12 + 24]
    cmp r15, FS_ENTRY_COUNT
    jae .read_empty
    inc qword [r12 + 24]
    mov rax, r15
    shl rax, 5
    lea rbx, [fs_table + rax]
    cmp byte [rbx + 20], 0
    je .readdir_next
    movzx eax, word [rbx + 29]
    cmp rax, r14
    jne .readdir_next
    mov rdi, r13
    xor eax, eax
    mov ecx, 4
    rep stosq
    lea rdi, [r13]
    lea rsi, [rbx]
    mov eax, r15d
    inc eax
    mov [rdi], eax
    mov al, [rsi + 20]
    mov [rdi + 4], al
    add rdi, 5
    mov ecx, 20
    rep movsb
    mov eax, 32
    jmp .return

.read:
    mov rax, [rsp + 72]
    cmp rax, FD_COUNT
    jae .bad_descriptor
    imul rax, rax, FD_ENTRY_SIZE
    mov ebx, [current_process]
    imul rbx, rbx, FD_COUNT * FD_ENTRY_SIZE
    lea r12, [fd_table + rbx + rax]
    cmp qword [r12], 4
    je .bad_descriptor
    mov rax, [r12]
    cmp rax, 2
    je .read_pipe
    cmp rax, 5
    jne .read_check_initramfs
    cmp qword [r12 + 16], 1
    je .bad_descriptor
    jmp .read_file_validate
.read_check_initramfs:
    cmp rax, 1
    je .read_file_validate
    cmp rax, 6
    je .bad_descriptor
    cmp qword [rsp + 72], 0
    je .read_keyboard
    jmp .bad_descriptor
.read_file_validate:
    mov r13, [rsp + 80]
    mov r14, [rsp + 88]
    test r14, r14
    jz .read_empty
    mov rax, r13
    cmp rax, 0x400000
    jb .bad_pointer
    add rax, r14
    jc .bad_pointer
    cmp rax, 0x420000
    ja .bad_pointer
    cmp qword [r12], 5
    jne .read_initramfs_file
    mov rdi, [r12 + 8]
    call fs_entry_from_id
    test rax, rax
    jz .bad_descriptor
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call fs_read_file
    jmp .return
.read_initramfs_file:
    jmp .read_file

.read_keyboard:
    mov r12, [rsp + 80]
    mov r13, [rsp + 88]
    test r13, r13
    jz .read_empty
    mov rax, r12
    cmp rax, 0x400000
    jb .bad_pointer
    add rax, r13
    jc .bad_pointer
    cmp rax, 0x420000
    ja .bad_pointer
    xor r14d, r14d

.read_key:
    mov eax, [keyboard_tail]
    cmp eax, [keyboard_head]
    je .read_block
    mov ebx, eax
    and ebx, 255
    movzx eax, byte [keyboard_buffer + rbx]
    inc dword [keyboard_tail]
    cmp al, 0x2A
    je .read_shift_down
    cmp al, 0x36
    je .read_shift_down
    cmp al, 0xAA
    je .read_shift_up
    cmp al, 0xB6
    je .read_shift_up
    test al, 0x80
    jnz .read_key
    cmp al, 0xE0
    je .read_key
    cmp al, 0x1C
    je .read_enter
    cmp al, 0x0E
    je .read_backspace
    movzx ebx, al
    cmp ebx, 127
    ja .read_key
    cmp byte [shift_down], 0
    je .read_unshifted
    cmp bl, 0x2B
    je .read_pipe_character
    cmp bl, 0x27
    je .read_colon_character
.read_unshifted:
    mov al, [keymap + rbx]
    test al, al
    jz .read_key
    jmp .read_store_character
.read_pipe_character:
    mov al, '|'
    jmp .read_store_character
.read_colon_character:
    mov al, ':'
.read_store_character:
    mov [r12 + r14], al
    inc r14
    call console_putc
    cmp r14, r13
    jb .read_key
    jmp .read_done

.read_backspace:
    test r14, r14
    jz .read_key
    dec r14
    mov byte [r12 + r14], 0
    mov al, 8
    call console_putc
    jmp .read_key
.read_shift_down:
    mov byte [shift_down], 1
    jmp .read_key
.read_shift_up:
    mov byte [shift_down], 0
    jmp .read_key

.read_block:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov qword [process_table + rbx], 4
    mov qword [process_table + rbx + 40], 1
    mov [process_table + rbx + 24], rsp
    mov [process_table + rbx + 56], r12
    mov [process_table + rbx + 64], r13
    mov [process_table + rbx + 72], r14
    call schedule_process

.read_resume:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov qword [process_table + rbx + 40], 0
    mov r12, [process_table + rbx + 56]
    mov r13, [process_table + rbx + 64]
    mov r14, [process_table + rbx + 72]
    jmp .read_key

.read_enter:
    mov byte [r12 + r14], 10
    inc r14
    mov al, 10
    call console_putc
.read_done:
    mov rax, r14
    jmp .return
.read_file:
    mov rax, [r12 + 24]
    cmp rax, [r12 + 16]
    jae .read_empty
    mov r15, [r12 + 16]
    sub r15, rax
    cmp r15, r14
    cmova r15, r14
    mov rsi, [r12 + 8]
    add rsi, rax
    mov rdi, r13
    mov rcx, r15
    rep movsb
    add [r12 + 24], r15
    mov rax, r15
    jmp .return
.read_pipe:
    mov rax, [r12 + 8]
    cmp rax, PIPE_COUNT
    jae .bad_descriptor
    imul rax, rax, PIPE_SIZE
    lea r15, [pipe_table + rax]
    mov r13, [rsp + 80]
    mov r14, [rsp + 88]
    test r14, r14
    jz .read_empty
    mov rax, r13
    cmp rax, 0x400000
    jb .bad_pointer
    add rax, r14
    jc .bad_pointer
    cmp rax, 0x420000
    ja .bad_pointer
    cmp qword [r15 + 40], 0
    jne .read_pipe_data
    cmp qword [r15 + 16], 0
    je .read_empty
    mov rax, -11
    jmp .return
.read_pipe_data:
    xor ebx, ebx
.read_pipe_loop:
    cmp rbx, r14
    jae .read_pipe_done
    cmp qword [r15 + 40], 0
    je .read_pipe_done
    mov rax, [r15 + 24]
    mov dl, [r15 + rax + 48]
    mov [r13 + rbx], dl
    inc rax
    and eax, 1023
    mov [r15 + 24], rax
    dec qword [r15 + 40]
    inc rbx
    jmp .read_pipe_loop
.read_pipe_done:
    mov rax, rbx
    jmp .return
.read_empty:
    xor eax, eax
    jmp .return
.bad_descriptor:
    mov rax, -9
    jmp .return

.no_entry:
    mov rax, -2
    jmp .return

.bad_pointer:
    mov rax, -14
    jmp .return

.exec:
    mov rdi, [rsp + 80]
    mov rsi, [rsp + 88]
    call copy_exec_arguments
    jc .bad_arguments
    mov rdi, [rsp + 40]
    call copy_exec_environment
    jc .bad_arguments
    mov rsi, [rsp + 72]
    cmp rsi, 0x400000
    jb .bad_pointer
    cmp rsi, 0x420000
    jae .bad_pointer
    call load_elf
    jc .exec_not_found
    call setup_user_arguments
    mov byte [process_kind], 2
    mov rsp, 0x90000
    jmp enter_user_mode
.exec_not_found:
    mov rax, -2
    jmp .return
.bad_arguments:
    mov rax, -22
    jmp .return

.exit:
    call close_process_fds
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    cmp qword [process_table + rbx + 16], 0
    je .exit_root
    mov r12, [process_table + rbx + 16]
    mov qword [process_table + rbx], 3
    xor r13d, r13d
.wake_parent:
    cmp r13d, PROCESS_COUNT
    jae .schedule_exit
    mov r14, r13
    imul r14, r14, PROCESS_SIZE
    cmp qword [process_table + r14], 2
    jne .next_parent
    cmp qword [process_table + r14 + 8], r12
    jne .next_parent
    mov qword [process_table + r14], 1
    mov rax, [process_table + rbx + 8]
    mov [process_table + r14 + 32], rax
    mov qword [process_table + rbx], 0
    jmp .schedule_exit
.next_parent:
    inc r13d
    jmp .wake_parent
.schedule_exit:
    call schedule_process
.exit_root:
    mov qword [process_table + rbx], 0
    mov byte [process_kind], 0
    mov rsp, 0x90000
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    jmp user_program_finished

.fork:
    call fork_process
    jmp .return

.wait:
    call wait_process
    test rax, rax
    js .return
    jmp syscall_entry.return

.yield:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov qword [process_table + rbx], 1
    mov [process_table + rbx + 24], rsp
    call schedule_process

.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    iretq

release_fd_entry:
    mov rax, [rdi]
    cmp rax, 2
    je .release_reader
    cmp rax, 3
    je .release_writer
    jmp .clear
.release_reader:
    mov rdx, [rdi + 8]
    imul rdx, rdx, PIPE_SIZE
    cmp qword [pipe_table + rdx + 8], 0
    je .clear
    dec qword [pipe_table + rdx + 8]
    jmp .release_check
.release_writer:
    mov rdx, [rdi + 8]
    imul rdx, rdx, PIPE_SIZE
    cmp qword [pipe_table + rdx + 16], 0
    je .clear
    dec qword [pipe_table + rdx + 16]
.release_check:
    cmp qword [pipe_table + rdx + 8], 0
    jne .clear
    cmp qword [pipe_table + rdx + 16], 0
    jne .clear
    mov qword [pipe_table + rdx], 0
.clear:
    mov qword [rdi], 0
    mov qword [rdi + 8], 0
    mov qword [rdi + 16], 0
    mov qword [rdi + 24], 0
    ret

close_process_fds:
    mov eax, [current_process]
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    lea rdi, [fd_table + rax]
    mov ecx, FD_COUNT
.close_next_fd:
    cmp qword [rdi], 0
    je .close_fd_done
    cmp qword [rdi], 4
    je .close_fd_done
    call release_fd_entry
.close_fd_done:
    add rdi, FD_ENTRY_SIZE
    loop .close_next_fd
    ret

fork_process:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov r12, process_table
    xor r13d, r13d
.find_slot:
    cmp qword [r12], 0
    je .slot_found
    add r12, PROCESS_SIZE
    inc r13d
    cmp r13d, PROCESS_COUNT
    jb .find_slot
    mov rax, -11
    ret
.slot_found:
    mov rax, [next_process_id]
    inc qword [next_process_id]
    mov [r12 + 8], rax
    mov rdx, [process_table + rbx + 8]
    mov [r12 + 16], rdx
    mov qword [r12 + 32], 0
    mov qword [r12], 1

    mov rax, r13
    shl rax, 21
    add rax, 0x800000
    mov rdi, rax
    mov rsi, 0x400000
    mov ecx, 0x4000
    rep movsq

    mov eax, [current_process]
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    lea rsi, [fd_table + rax]
    mov rax, r13
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    lea rdi, [fd_table + rax]
    mov ecx, FD_COUNT * FD_ENTRY_SIZE / 8
    rep movsq
    mov eax, r13d
    imul rax, rax, FD_COUNT * FD_ENTRY_SIZE
    lea r15, [fd_table + rax]
    mov ecx, FD_COUNT
.inherit_fd:
    cmp qword [r15], 2
    je .inherit_reader
    cmp qword [r15], 3
    je .inherit_writer
    jmp .inherit_next
.inherit_reader:
    mov rax, [r15 + 8]
    imul rax, rax, PIPE_SIZE
    inc qword [pipe_table + rax + 8]
    jmp .inherit_next
.inherit_writer:
    mov rax, [r15 + 8]
    imul rax, rax, PIPE_SIZE
    inc qword [pipe_table + rax + 16]
.inherit_next:
    add r15, FD_ENTRY_SIZE
    loop .inherit_fd

    lea rsi, [rsp + 8]
    mov rax, [tss + 4]
    sub rax, rsi
    mov rcx, rax
    mov rdx, r13
    inc rdx
    shl rdx, 14
    add rdx, PROCESS_STACK_BASE
    sub rdx, rcx
    mov [r12 + 24], rdx
    mov rdi, rdx
    rep movsb

    mov rax, [r12 + 8]
    ret

wait_process:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    mov r12, [process_table + rbx + 8]
    xor r13d, r13d
    xor r14d, r14d
.scan_children:
    cmp r13d, PROCESS_COUNT
    jae .scan_done
    mov r15, r13
    imul r15, r15, PROCESS_SIZE
    cmp qword [process_table + r15], 0
    je .next_child
    cmp qword [process_table + r15 + 16], r12
    jne .next_child
    mov r14d, 1
    cmp qword [process_table + r15], 3
    jne .next_child
    mov rax, [process_table + r15 + 8]
    mov qword [process_table + r15], 0
    ret
.next_child:
    inc r13d
    jmp .scan_children
.scan_done:
    test r14d, r14d
    jz .no_children
    mov qword [process_table + rbx], 2
    lea rax, [rsp + 8]
    mov [process_table + rbx + 24], rax
    call schedule_process
.no_children:
    mov rax, -10
    ret

schedule_process:
    mov ecx, [current_process]
    inc ecx
    xor r13d, r13d
.find_runnable:
    cmp r13d, PROCESS_COUNT
    jae .no_other
    cmp ecx, PROCESS_COUNT
    jb .index_ready
    xor ecx, ecx
.index_ready:
    mov r14, rcx
    imul r14, r14, PROCESS_SIZE
    cmp qword [process_table + r14], 1
    je .switch
    inc ecx
    inc r13d
    jmp .find_runnable

.no_other:
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    cmp qword [process_table + rbx], 2
    jne .no_runnable
    mov qword [process_table + rbx], 1
    mov qword [process_table + rbx + 32], -10
    mov ecx, [current_process]
    jmp .index_ready
.no_runnable:
    sti
    hlt
    cli
    mov ecx, [current_process]
    inc ecx
    xor r13d, r13d
    jmp .find_runnable

.switch:
    cmp ecx, [current_process]
    je .same_process

    mov r15d, ecx
    mov ebx, [current_process]
    imul rbx, rbx, PROCESS_SIZE
    cmp qword [process_table + rbx], 0
    je .restore_selected
    cmp qword [process_table + rbx], 3
    je .restore_selected

    mov rax, 0x800000
    mov edx, [current_process]
    shl rdx, 21
    add rax, rdx
    mov rdi, rax
    mov rsi, 0x400000
    mov ecx, 0x4000
    rep movsq

.restore_selected:
    mov ecx, r15d
    mov [current_process], ecx
    mov r14, rcx
    imul r14, r14, PROCESS_SIZE
    add r14, process_table
    mov ecx, [current_process]
    shl rcx, 21
    mov rsi, 0x800000
    add rsi, rcx
    mov rdi, 0x400000
    mov ecx, 0x4000
    rep movsq
    jmp .selected

.same_process:
    mov r14, rcx
    imul r14, r14, PROCESS_SIZE
    add r14, process_table
.selected:
    mov ecx, [current_process]
    inc ecx
    shl rcx, 14
    add rcx, PROCESS_STACK_BASE
    mov [tss + 4], rcx
    cmp qword [r14 + 48], 0
    jne .timer_context
    cmp qword [r14 + 40], 1
    je .keyboard_context
    mov rax, [r14 + 32]
    jmp .restore_context
.timer_context:
    mov qword [r14 + 48], 0
    mov qword [r14 + 32], 0
    mov rsp, [r14 + 24]
    jmp timer_irq.return
.keyboard_context:
    mov rsp, [r14 + 24]
    jmp syscall_entry.read_resume
.restore_context:
    mov qword [r14 + 32], 0
    mov rsp, [r14 + 24]
    jmp syscall_entry.return

copy_exec_arguments:
    cmp rsi, 1
    jb .invalid
    cmp rsi, 8
    ja .invalid
    mov r12, rsi
    mov r13, rdi
    cmp r13, 0x400000
    jb .invalid
    mov rax, r12
    shl rax, 3
    add rax, r13
    jc .invalid
    cmp rax, 0x420000
    ja .invalid
    mov [exec_argc], r12
    mov qword [exec_data_size], 0
    xor r14d, r14d
.argument:
    mov r15, [r13 + r14 * 8]
    cmp r15, 0x400000
    jb .invalid
    cmp r15, 0x420000
    jae .invalid
    mov rbx, [exec_data_size]
.character:
    cmp r15, 0x420000
    jae .invalid
    cmp rbx, 1024
    jae .invalid
    mov al, [r15]
    mov [exec_arg_data + rbx], al
    inc r15
    inc rbx
    test al, al
    jnz .character
    mov [exec_data_size], rbx
    inc r14
    cmp r14, r12
    jb .argument
    clc
    ret
.invalid:
    stc
    ret

copy_exec_environment:
    mov qword [exec_envc], 0
    mov qword [exec_env_size], 0
    test rdi, rdi
    jz .valid
    cmp rdi, 0x400000
    jb .invalid
    cmp rdi, 0x420000
    jae .invalid
    mov r13, rdi
    xor r14d, r14d
.entry:
    cmp r14, 8
    ja .invalid
    lea rax, [r13 + r14 * 8]
    cmp rax, 0x420000
    jae .invalid
    mov r15, [rax]
    test r15, r15
    jz .valid
    cmp r14, 8
    jae .invalid
    cmp r15, 0x400000
    jb .invalid
    cmp r15, 0x420000
    jae .invalid
    mov rbx, [exec_env_size]
.character:
    cmp r15, 0x420000
    jae .invalid
    cmp rbx, 1024
    jae .invalid
    mov al, [r15]
    mov [exec_env_data + rbx], al
    inc r15
    inc rbx
    test al, al
    jnz .character
    mov [exec_env_size], rbx
    inc r14
    mov [exec_envc], r14
    jmp .entry
.valid:
    clc
    ret
.invalid:
    stc
    ret

setup_user_arguments:
    mov rdi, 0x41E100
    lea rsi, [exec_arg_data]
    mov rcx, [exec_data_size]
    rep movsb

    mov r12, [exec_argc]
    xor r13d, r13d
    xor r14d, r14d
    mov rdi, 0x41E000
.pointer:
    cmp r14, r12
    jae .done
    mov rax, 0x41E100
    add rax, r13
    mov [rdi + r14 * 8], rax
.string_end:
    cmp byte [exec_arg_data + r13], 0
    je .next_argument
    inc r13
    jmp .string_end
.next_argument:
    inc r13
    inc r14
    jmp .pointer
.done:
    mov qword [rdi + r14 * 8], 0

    mov rdi, 0x41E500
    lea rsi, [exec_env_data]
    mov rcx, [exec_env_size]
    rep movsb

    mov r12, [exec_envc]
    xor r13d, r13d
    xor r14d, r14d
    mov rdi, 0x41DF00
.environment_pointer:
    cmp r14, r12
    jae .environment_done
    mov rax, 0x41E500
    add rax, r13
    mov [rdi + r14 * 8], rax
.environment_string_end:
    cmp byte [exec_env_data + r13], 0
    je .next_environment
    inc r13
    jmp .environment_string_end
.next_environment:
    inc r13
    inc r14
    jmp .environment_pointer
.environment_done:
    mov qword [rdi + r14 * 8], 0
    mov rdi, r12
    mov rdx, 0x41DF00
    mov rsi, 0x41E000
    mov rdi, [exec_argc]
    ret

find_file:
    mov r8, rdi
    mov r9, 0x20000
    mov rax, [r9]
    mov rdx, 0x3130305346584F46
    cmp rax, rdx
    jne .not_found
    mov r10d, [r9 + 8]
    cmp r10d, 32
    ja .not_found
    test r10d, r10d
    jz .not_found
    mov eax, [r9 + 12]
    cmp rax, 49152
    ja .not_found
    mov r15, r10
    imul r15, 48
    add r15, 16
    cmp r15, rax
    ja .not_found
    lea r11, [r9 + 16]
.entry:
    test r10d, r10d
    jz .not_found
    xor edi, edi
.name:
    cmp edi, 32
    jae .next_entry
    lea rax, [r8 + rdi]
    cmp rax, 0x420000
    jae .not_found
    mov al, [r8 + rdi]
    cmp al, [r11 + rdi]
    jne .next_entry
    test al, al
    jz .found
    inc edi
    jmp .name
.next_entry:
    add r11, 48
    dec r10d
    jmp .entry
.found:
    mov rax, [r11 + 32]
    mov rdx, [r11 + 40]
    cmp rax, r15
    jb .not_found
    mov rcx, rax
    add rcx, rdx
    jc .not_found
    mov esi, [r9 + 12]
    cmp rcx, rsi
    ja .not_found
    add rax, r9
    clc
    ret
.not_found:
    stc
    ret

%include "kernel/fs.asm"

load_elf:
    mov byte [elf_load_count], 0
    mov byte [elf_entry_found], 0
    cmp byte [fs_ready], 1
    jne .initramfs
    mov rdi, rsi
    call fs_resolve
    jc .initramfs
    test rax, rax
    jz .invalid
    cmp byte [rax + 20], 2
    jne .invalid
    mov rdi, rax
    call fs_stage_file
    jc .invalid
    jmp .file_ready
.initramfs:
    mov rdi, rsi
    call find_file
    jc .invalid
.file_ready:
    mov [elf_file], rax
    mov [elf_size], rdx
    cmp rdx, 64
    jb .invalid
    cmp dword [rax], 0x464C457F
    jne .invalid
    cmp byte [rax + 4], 2
    jne .invalid
    cmp byte [rax + 5], 1
    jne .invalid
    cmp byte [rax + 6], 1
    jne .invalid
    cmp word [rax + 16], 2
    jne .invalid
    cmp word [rax + 18], 62
    jne .invalid
    mov rdx, [rax + 24]
    cmp rdx, 0x400000
    jb .invalid
    cmp rdx, 0x420000
    jae .invalid
    mov [user_entry], rdx
    mov r8, [rax + 32]
    movzx r9d, word [rax + 54]
    movzx r10d, word [rax + 56]
    cmp r9d, 56
    jne .invalid
    cmp r10d, 32
    ja .invalid
    test r10d, r10d
    jz .invalid
    mov rax, r9
    imul rax, r10
    jo .invalid
    add rax, r8
    jc .invalid
    cmp rax, [elf_size]
    ja .invalid

    mov edi, 0x400000
    xor eax, eax
    mov ecx, 0x4000
    rep stosq

    mov rbx, [elf_file]
    lea r11, [rbx + r8]
.program_header:
    test r10d, r10d
    jz .loaded
    cmp dword [r11], 1
    jne .next_program_header

    mov rax, [r11 + 16]
    cmp rax, 0x400000
    jb .invalid
    mov rdx, [r11 + 40]
    test rdx, rdx
    jz .next_program_header
    inc byte [elf_load_count]
    add rax, rdx
    jc .invalid
    cmp rax, 0x420000
    ja .invalid
    mov rcx, [r11 + 32]
    cmp rcx, rdx
    ja .invalid
    test dword [r11 + 4], 1
    jz .not_executable_segment
    mov rax, [user_entry]
    cmp rax, [r11 + 16]
    jb .not_executable_segment
    cmp rax, [r11 + 16]
    je .entry_in_segment
    mov rdx, [r11 + 40]
    add rdx, [r11 + 16]
    cmp rax, rdx
    jae .not_executable_segment
.entry_in_segment:
    mov byte [elf_entry_found], 1
.not_executable_segment:
    mov rdi, [r11 + 16]
    mov rsi, [r11 + 8]
    mov rcx, [r11 + 32]
    mov rax, rsi
    add rax, rcx
    jc .invalid
    cmp rax, [elf_size]
    ja .invalid
    add rsi, rbx
    rep movsb

    mov rcx, [r11 + 40]
    sub rcx, [r11 + 32]
    xor eax, eax
    rep stosb

.next_program_header:
    add r11, r9
    dec r10d
    jmp .program_header
.loaded:
    cmp byte [elf_load_count], 0
    je .invalid
    cmp byte [elf_entry_found], 1
    jne .invalid
    clc
    ret
.invalid:
    stc
    ret

console_putc:
    cmp al, 10
    je .newline
    cmp al, 8
    je .backspace
    cmp al, 13
    je .done

    mov rdi, [user_cursor]
    cmp rdi, 2000
    jae .scroll
    mov [text_character], al
    mov [text_cell], edi
    cmp byte [graphics_ready], 1
    jne .store_text_cell
    call draw_graphics_text_cell
    mov edi, [text_cell]
.store_text_cell:
    mov al, [text_character]
    shl rdi, 1
    mov ah, 0x0F
    mov [0xB8000 + rdi], ax
    shr rdi, 1
    inc rdi
    mov [user_cursor], rdi
    cmp rdi, 2000
    jb .done
    jmp .scroll

.newline:
    mov rax, [user_cursor]
    xor edx, edx
    mov ecx, 80
    div rcx
    inc rax
    imul rax, rax, 80
    mov [user_cursor], rax
    cmp rax, 2000
    jb .done
    jmp .scroll

.backspace:
    mov rdi, [user_cursor]
    test rdi, rdi
    jz .done
    dec rdi
    mov [user_cursor], rdi
    mov [text_cell], edi
    mov byte [text_character], ' '
    cmp byte [graphics_ready], 1
    jne .clear_text_cell
    call draw_graphics_text_cell
    mov rdi, [user_cursor]
.clear_text_cell:
    shl rdi, 1
    mov word [0xB8000 + rdi], 0x0720
    ret

.scroll:
    cmp byte [graphics_ready], 1
    jne .scroll_text
    mov rsi, [framebuffer_address]
    mov rdi, rsi
    mov eax, [framebuffer_pitch]
    shl eax, 4
    add rsi, rax
    mov ecx, [framebuffer_pitch]
    imul ecx, 16 * 24
    shr ecx, 3
    rep movsq
    mov edi, [framebuffer_pitch]
    imul edi, 16 * 24
    add rdi, [framebuffer_address]
    mov eax, [framebuffer_pitch]
    shr eax, 1
    mov ecx, eax
    mov eax, 0
    rep stosw
    mov qword [user_cursor], 1920
    ret
.scroll_text:
    mov rsi, 0xB80A0
    mov rdi, 0xB8000
    mov ecx, 1920
    rep movsw
    mov edi, 0xB8F00
    mov ax, 0x0720
    mov ecx, 80
    rep stosw
    mov qword [user_cursor], 1920
.done:
    ret

setup_framebuffer:
    mov byte [graphics_ready], 0
    cmp byte [0x60FF], 1
    jne .done
    cmp word [0x6010], 2048
    jb .done
    cmp word [0x6012], 1024
    jne .done
    cmp word [0x6014], 768
    jne .done
    movzx eax, word [0x6010]
    mov [framebuffer_pitch], eax
    movzx eax, word [0x6012]
    mov [framebuffer_width], eax
    movzx eax, word [0x6014]
    mov [framebuffer_height], eax
    mov eax, [0x6028]
    mov edx, eax
    and eax, 0x001FFFFF
    mov ecx, [framebuffer_pitch]
    imul ecx, [framebuffer_height]
    add ecx, eax
    cmp ecx, 0x200000
    ja .done
    mov eax, edx
    and eax, 0x001FFFFF
    add rax, FRAMEBUFFER_VIRTUAL
    mov [framebuffer_address], rax
    mov byte [graphics_ready], 1
.done:
    ret

fill_rect:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    cmp byte [terminal_rendering], 0
    je .coordinates_ready
    sub r12d, [terminal_window_x]
    add r12d, 2
    sub r13d, [terminal_window_y]
    add r13d, 2
.coordinates_ready:
    mov r14d, edx
    mov r15d, ecx
    mov ebx, r8d
.row:
    test r15d, r15d
    jz .done
    mov eax, r13d
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, r12d
    shl rdx, 1
    mov edi, edx
    add rdi, rax
    mov ecx, r14d
    mov eax, ebx
    rep stosw
    inc r13d
    dec r15d
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

draw_glyph:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    cmp byte [terminal_rendering], 0
    je .coordinates_ready
    sub r12d, [terminal_window_x]
    add r12d, 2
    sub r13d, [terminal_window_y]
    add r13d, 2
.coordinates_ready:
    mov r14d, edx
    mov r15d, ecx
    shl r15d, 4
    mov ebx, r8d
    xor r10d, r10d
.glyph_row:
    cmp r10d, 16
    jae .done
    movzx r9d, byte [FONT_PHYSICAL + r15]
    mov eax, r13d
    add eax, r10d
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, r12d
    shl rdx, 1
    add rax, rdx
    mov rdi, rax
    mov r11d, 8
.glyph_pixel:
    test r9b, 0x80
    jz .background_pixel
    mov ax, r14w
    jmp .store_pixel
.background_pixel:
    mov ax, bx
.store_pixel:
    mov [rdi], ax
    add rdi, 2
    shl r9b, 1
    dec r11d
    jnz .glyph_pixel
    inc r15d
    inc r10d
    jmp .glyph_row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

draw_string:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov ebp, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, r8d
    mov rbx, rcx
.next_character:
    movzx ecx, byte [rbx]
    test ecx, ecx
    jz .done
    inc rbx
    cmp ecx, 10
    je .newline
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov r8d, r15d
    call draw_glyph
    add r12d, 8
    jmp .next_character
.newline:
    mov r12d, ebp
    add r13d, 16
    jmp .next_character
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

clear_framebuffer:
    mov edi, 0
    mov esi, 0
    mov edx, [framebuffer_width]
    mov ecx, [framebuffer_height]
    mov r8d, 0
    call fill_rect
    ret

draw_mouse_cursor:
    cmp byte [graphics_ready], 1
    jne .done
    call erase_mouse_cursor
    push rbx
    push r12
    push r13
    push r14
    pushfq
    cli
    mov eax, [mouse_x]
    mov [mouse_cursor_x], eax
    mov eax, [mouse_y]
    mov [mouse_cursor_y], eax
    xor ebx, ebx
.cursor_row:
    cmp ebx, 12
    jae .cursor_drawn
    mov eax, [mouse_cursor_y]
    add eax, ebx
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, [mouse_cursor_x]
    shl edx, 1
    add rax, rdx
    mov rsi, rax
    mov eax, ebx
    shl eax, 4
    lea rdi, [mouse_cursor_saved + rax]
    movzx ecx, byte [mouse_cursor_widths + rbx]
    rep movsw

    mov edi, [mouse_cursor_x]
    mov esi, [mouse_cursor_y]
    add esi, ebx
    movzx edx, byte [mouse_cursor_widths + rbx]
    mov ecx, 1
    mov r8d, 0
    call fill_rect
    cmp ebx, 2
    jb .next_row
    movzx eax, byte [mouse_cursor_widths + rbx]
    cmp eax, 2
    jbe .next_row
    mov edi, [mouse_cursor_x]
    inc edi
    mov esi, [mouse_cursor_y]
    add esi, ebx
    sub eax, 2
    mov edx, eax
    mov ecx, 1
    mov r8d, 0xFFFF
    call fill_rect
.next_row:
    inc ebx
    jmp .cursor_row
.cursor_drawn:
    mov byte [mouse_cursor_drawn], 1
    popfq
    pop r14
    pop r13
    pop r12
    pop rbx
.done:
    ret

erase_mouse_cursor:
    cmp byte [graphics_ready], 1
    jne .done
    cmp byte [mouse_cursor_drawn], 0
    je .done
    push rbx
    pushfq
    cli
    xor ebx, ebx
.restore_row:
    cmp ebx, 12
    jae .restored
    mov eax, [mouse_cursor_y]
    add eax, ebx
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, [mouse_cursor_x]
    shl edx, 1
    add rax, rdx
    mov rdi, rax
    mov eax, ebx
    shl eax, 4
    lea rsi, [mouse_cursor_saved + rax]
    movzx ecx, byte [mouse_cursor_widths + rbx]
    rep movsw
    inc ebx
    jmp .restore_row
.restored:
    mov byte [mouse_cursor_drawn], 0
    popfq
    pop rbx
.done:
    ret

draw_terminal_window:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, [terminal_window_x]
    mov r12d, [terminal_window_y]

    lea edi, [rbx - 2]
    lea esi, [r12 - 2]
    mov edx, TERMINAL_WINDOW_WIDTH + 4
    mov ecx, TERMINAL_WINDOW_HEIGHT + 4
    mov r8d, 0x7BEF
    call fill_rect

    mov edi, ebx
    mov esi, r12d
    mov edx, TERMINAL_WINDOW_WIDTH
    mov ecx, TERMINAL_WINDOW_HEIGHT
    mov r8d, 0x0000
    call fill_rect

    mov edi, ebx
    mov esi, r12d
    mov edx, TERMINAL_WINDOW_WIDTH
    mov ecx, 36
    mov r8d, 0x2104
    cmp byte [screen_mode], 1
    jne .title_bar_color
    mov r8d, 0x3186
.title_bar_color:
    mov r15d, r8d
    call fill_rect

    lea edi, [rbx + 12]
    lea esi, [r12 + 10]
    mov edx, 0xFFFF
    mov r8d, r15d
    mov rcx, terminal_title
    call draw_string

    lea edi, [rbx + TERMINAL_WINDOW_WIDTH - 30]
    lea esi, [r12 + 6]
    mov edx, 24
    mov ecx, 24
    mov r8d, 0x7800
    cmp byte [screen_mode], 1
    jne .close_button_color
    mov r8d, 0xF800
.close_button_color:
    call fill_rect
    lea edi, [rbx + TERMINAL_WINDOW_WIDTH - 23]
    lea esi, [r12 + 10]
    mov edx, 0xFFFF
    mov r8d, 0xF800
    mov rcx, terminal_close_label
    call draw_string

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

dispatch_mouse_click:
    cmp byte [terminal_visible], 0
    je .desktop_window_click
    mov eax, [mouse_x]
    cmp eax, [terminal_window_x]
    jb .outside_terminal
    mov edx, [terminal_window_x]
    add edx, TERMINAL_WINDOW_WIDTH
    cmp eax, edx
    jae .outside_terminal
    mov eax, [mouse_y]
    cmp eax, [terminal_window_y]
    jb .outside_terminal
    mov edx, [terminal_window_y]
    add edx, TERMINAL_WINDOW_HEIGHT
    cmp eax, edx
    jae .outside_terminal

    mov byte [screen_mode], 1
    mov edx, [terminal_window_y]
    add edx, 36
    cmp eax, edx
    jae .focus_terminal_content
    mov edx, [terminal_window_y]
    add edx, 6
    cmp eax, edx
    jb .start_terminal_drag
    mov edx, [terminal_window_y]
    add edx, 30
    cmp eax, edx
    jae .start_terminal_drag
    mov eax, [mouse_x]
    mov edx, [terminal_window_x]
    add edx, TERMINAL_WINDOW_WIDTH - 30
    cmp eax, edx
    jb .start_terminal_drag
    add edx, 24
    cmp eax, edx
    jae .start_terminal_drag
    mov byte [terminal_visible], 0
    mov byte [terminal_drag], 0
    mov byte [screen_mode], 0
    call draw_desktop
    call draw_mouse_cursor
    ret
.start_terminal_drag:
    mov byte [terminal_drag], 1
    mov eax, [mouse_x]
    mov [terminal_drag_mouse_x], eax
    mov eax, [mouse_y]
    mov [terminal_drag_mouse_y], eax
    call terminal_screen
    call draw_mouse_cursor
    ret
.focus_terminal_content:
    mov byte [terminal_drag], 0
    call terminal_screen
    call draw_mouse_cursor
    ret

.desktop_window_click:
    cmp byte [welcome_visible], 1
    jne .desktop_click
    mov eax, [mouse_x]
    cmp eax, 898
    jb .desktop_click
    cmp eax, 940
    jae .desktop_click
    mov eax, [mouse_y]
    cmp eax, 114
    jb .desktop_click
    cmp eax, 148
    jae .desktop_click
    mov byte [welcome_visible], 0
    call draw_desktop
    call draw_mouse_cursor
    ret
.outside_terminal:
    mov byte [terminal_drag], 0
    cmp byte [screen_mode], 0
    je .desktop_click
    mov byte [screen_mode], 0
    call terminal_screen
.desktop_click:
    cmp byte [applications_menu_open], 1
    jne .desktop_controls
    mov eax, [mouse_y]
    cmp eax, 36
    jb .close_applications_menu
    cmp eax, 196
    jae .close_applications_menu
    mov eax, [mouse_x]
    cmp eax, 8
    jb .close_applications_menu
    cmp eax, 212
    jae .close_applications_menu
    mov eax, [mouse_y]
    cmp eax, 78
    jb .menu_terminal
    cmp eax, 114
    jb .menu_shell
    cmp eax, 154
    jb .menu_shutdown
    cmp eax, 196
    jb .menu_about
    jmp .menu_shutdown
.close_applications_menu:
    mov byte [applications_menu_open], 0
    call draw_desktop
    mov eax, [mouse_y]
    cmp eax, 36
    jb .closed_top_panel
    cmp eax, 728
    jae .closed_bottom_panel
    jmp .desktop_controls
.closed_top_panel:
    mov eax, [mouse_x]
    cmp eax, 8
    jb .desktop_controls
    cmp eax, 134
    jb .done
    jmp .desktop_controls
.closed_bottom_panel:
    mov eax, [mouse_x]
    cmp eax, 8
    jb .desktop_controls
    cmp eax, 126
    jb .done
.desktop_controls:
    mov eax, [mouse_y]
    cmp eax, 36
    jb .panel_click
    cmp eax, 728
    jae .panel_click
    cmp eax, 80
    jb .done
    cmp eax, 176
    jb .terminal_icon
    cmp eax, 200
    jb .done
    cmp eax, 290
    jb .shell_icon
.done:
    ret
.panel_click:
    mov eax, [mouse_y]
    cmp eax, 36
    jae .bottom_panel
    mov eax, [mouse_x]
    cmp eax, 8
    jb .done
    cmp eax, 134
    jb .toggle_applications_menu
    cmp eax, 172
    jb .open_terminal
    cmp eax, 210
    jb .open_shell
    cmp eax, 248
    jb .open_desktop
    ret
.bottom_panel:
    cmp eax, 728
    jb .done
    mov eax, [mouse_x]
    cmp eax, 8
    jb .done
    cmp eax, 126
    jb .toggle_applications_menu
    cmp eax, 292
    jb .open_terminal
    cmp eax, 456
    jb .open_shell
    ret
.terminal_icon:
    mov eax, [mouse_x]
    cmp eax, 32
    jb .done
    cmp eax, 104
    jae .done
    jmp .open_terminal
.shell_icon:
    mov eax, [mouse_x]
    cmp eax, 32
    jb .done
    cmp eax, 104
    jae .done
    jmp .open_shell
.toggle_applications_menu:
    xor byte [applications_menu_open], 1
    call draw_desktop
    call draw_mouse_cursor
    ret
.menu_terminal:
    mov byte [applications_menu_open], 0
    jmp .open_terminal
.menu_shell:
    mov byte [applications_menu_open], 0
    jmp .open_shell
.menu_shutdown:
    mov byte [applications_menu_open], 0
    mov byte [screen_mode], 1
    mov byte [terminal_visible], 1
    call app_shutdown_run
.menu_about:
    mov byte [applications_menu_open], 0
    mov byte [welcome_visible], 1
    call draw_desktop
    call draw_mouse_cursor
    ret
.open_terminal:
    mov byte [applications_menu_open], 0
    mov byte [screen_mode], 1
    mov byte [terminal_visible], 1
    mov byte [terminal_drag], 0
    call draw_desktop
    call draw_mouse_cursor
    ret
.open_desktop:
    mov byte [applications_menu_open], 0
    mov byte [screen_mode], 0
    mov byte [terminal_visible], 0
    mov byte [terminal_drag], 0
    call draw_desktop
    call draw_mouse_cursor
    ret
.open_shell:
    mov byte [applications_menu_open], 0
    mov byte [screen_mode], 0
    mov byte [terminal_visible], 0
    mov byte [terminal_drag], 0
    call launch_c_shell
    ret

drag_terminal_window:
    call restore_terminal_background
    mov eax, [mouse_x]
    sub eax, [terminal_drag_mouse_x]
    add [terminal_window_x], eax
    mov eax, [mouse_y]
    sub eax, [terminal_drag_mouse_y]
    add [terminal_window_y], eax
    mov eax, [mouse_x]
    mov [terminal_drag_mouse_x], eax
    mov eax, [mouse_y]
    mov [terminal_drag_mouse_y], eax

    cmp dword [terminal_window_x], 2
    jge .clamp_x_high
    mov dword [terminal_window_x], 2
.clamp_x_high:
    cmp dword [terminal_window_x], 312
    jle .clamp_y_low
    mov dword [terminal_window_x], 312
.clamp_y_low:
    cmp dword [terminal_window_y], 38
    jge .clamp_y_high
    mov dword [terminal_window_y], 38
.clamp_y_high:
    cmp dword [terminal_window_y], 220
    jle .redraw
    mov dword [terminal_window_y], 220
.redraw:
    call save_terminal_background
    call terminal_screen
    ret

save_terminal_background:
    push r12
    xor r12d, r12d
.row:
    cmp r12d, TERMINAL_SAVE_HEIGHT
    jae .done
    mov eax, r12d
    add eax, [terminal_window_y]
    sub eax, 2
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, [terminal_window_x]
    sub edx, 2
    shl edx, 1
    add rax, rdx
    mov rsi, rax
    mov eax, r12d
    imul eax, TERMINAL_SAVE_WIDTH * 2
    mov edi, TERMINAL_SAVE_BUFFER
    add rdi, rax
    mov ecx, TERMINAL_SAVE_WIDTH
    rep movsw
    inc r12d
    jmp .row
.done:
    pop r12
    ret

restore_terminal_background:
    push r12
    xor r12d, r12d
.row:
    cmp r12d, TERMINAL_SAVE_HEIGHT
    jae .done
    mov eax, r12d
    add eax, [terminal_window_y]
    sub eax, 2
    imul eax, [framebuffer_pitch]
    add rax, [framebuffer_address]
    mov edx, [terminal_window_x]
    sub edx, 2
    shl edx, 1
    add rax, rdx
    mov rdi, rax
    mov eax, r12d
    imul eax, TERMINAL_SAVE_WIDTH * 2
    mov esi, TERMINAL_SAVE_BUFFER
    add rsi, rax
    mov ecx, TERMINAL_SAVE_WIDTH
    rep movsw
    inc r12d
    jmp .row
.done:
    pop r12
    ret

draw_graphical_desktop:
    FILL_RECT 0, 0, 1024, 768, 0x2B54
    FILL_RECT 0, 36, 1024, 112, 0x2B54
    FILL_RECT 0, 148, 1024, 116, 0x2B13
    FILL_RECT 0, 264, 1024, 112, 0x22F2
    FILL_RECT 0, 376, 1024, 112, 0x22B1
    FILL_RECT 0, 488, 1024, 116, 0x1A70
    FILL_RECT 0, 604, 1024, 124, 0x1A2E
    FILL_RECT 0, 0, 1024, 36, 0x2125
    FILL_RECT 0, 728, 1024, 40, 0x2125

    ; XFCE-style panels and a compact welcome window on the wallpaper.
    FILL_RECT 8, 4, 126, 28, 0x3A09
    FILL_RECT 140, 4, 32, 28, 0x31A7
    FILL_RECT 178, 4, 32, 28, 0x31A7
    FILL_RECT 216, 4, 32, 28, 0x31A7
    FILL_RECT 8, 734, 118, 28, 0x3A09
    FILL_RECT 136, 734, 156, 28, 0x31A7
    FILL_RECT 300, 734, 156, 28, 0x31A7
    FILL_RECT 848, 734, 164, 28, 0x31A7

    ; Desktop shortcuts.
    FILL_RECT 40, 88, 52, 48, 0xE5C9
    FILL_RECT 48, 80, 36, 14, 0xF6AE
    FILL_RECT 40, 210, 52, 48, 0x4C7A
    FILL_RECT 48, 218, 36, 4, 0xDF5F
    FILL_RECT 48, 226, 36, 4, 0xDF5F
    FILL_RECT 48, 234, 28, 4, 0xDF5F

    ; About window, shown only when selected from Applications.
    cmp byte [welcome_visible], 1
    jne .welcome_hidden
    FILL_RECT 238, 120, 704, 432, 0x116A
    FILL_RECT 244, 112, 704, 432, 0x2146
    FILL_RECT 244, 112, 704, 38, 0x31A8
    FILL_RECT 244, 150, 704, 394, 0xEF7E
    FILL_RECT 268, 174, 656, 78, 0xFFFFFF
    FILL_RECT 268, 268, 208, 88, 0xFFFFFF
    FILL_RECT 492, 268, 208, 88, 0xFFFFFF
    FILL_RECT 716, 268, 208, 88, 0xFFFFFF
    FILL_RECT 268, 372, 656, 132, 0xFFFFFF
    FILL_RECT 902, 118, 34, 26, 0xBA49
.welcome_hidden:

    DRAW_TEXT 20, 10, 0xFFFF, 0x3A09, desktop_apps
    cmp byte [fs_ready], 1
    jne .storage_offline
    DRAW_TEXT 862, 10, 0x9F4E, 0x2125, desktop_status
    jmp .status_drawn
.storage_offline:
    DRAW_TEXT 838, 10, 0xFC50, 0x2125, desktop_storage_offline
.status_drawn:
    DRAW_TEXT 152, 10, 0xDEFD, 0x31A7, panel_terminal
    DRAW_TEXT 190, 10, 0xDEFD, 0x31A7, panel_shell
    DRAW_TEXT 228, 10, 0xDEFD, 0x31A7, panel_files
    DRAW_TEXT 20, 740, 0xFFFF, 0x3A09, panel_menu
    DRAW_TEXT 148, 740, 0xDEFD, 0x31A7, panel_terminal
    DRAW_TEXT 312, 740, 0xDEFD, 0x31A7, panel_shell
    DRAW_TEXT 864, 740, 0xBE19, 0x31A7, taskbar_resolution

    DRAW_TEXT 46, 148, 0xFFFF, 0x2B54, icon_terminal
    DRAW_TEXT 46, 270, 0xFFFF, 0x2B54, icon_shell
    cmp byte [welcome_visible], 1
    jne .welcome_text_hidden
    DRAW_TEXT 270, 124, 0xFFFF, 0x31A8, welcome_title
    DRAW_TEXT 918, 123, 0xFFFF, 0xBA49, terminal_close_label
    DRAW_TEXT 286, 190, 0x21A8, 0xFFFF, desktop_welcome_graphical
    DRAW_TEXT 286, 222, 0x6BB0, 0xFFFF, desktop_hint_graphical
    DRAW_TEXT 284, 284, 0x3B73, 0xFFFF, welcome_terminal
    DRAW_TEXT 508, 284, 0x3B73, 0xFFFF, welcome_shell
    DRAW_TEXT 732, 284, 0x3B73, 0xFFFF, welcome_storage
    DRAW_TEXT 284, 316, 0x6BB0, 0xFFFF, welcome_terminal_hint
    DRAW_TEXT 508, 316, 0x6BB0, 0xFFFF, welcome_shell_hint
    DRAW_TEXT 732, 316, 0x6BB0, 0xFFFF, welcome_storage_hint
    DRAW_TEXT 286, 390, 0x21A8, 0xFFFF, welcome_about
    DRAW_TEXT 286, 422, 0x6BB0, 0xFFFF, desktop_program_hint_graphical
    DRAW_TEXT 286, 454, 0x6BB0, 0xFFFF, desktop_files_hint_graphical
.welcome_text_hidden:
    cmp byte [applications_menu_open], 1
    jne .done
    FILL_RECT 8, 36, 204, 160, 0x2146
    FILL_RECT 10, 38, 200, 36, 0x31A7
    FILL_RECT 10, 78, 200, 36, 0x31A7
    FILL_RECT 10, 118, 200, 36, 0x31A7
    FILL_RECT 10, 158, 200, 36, 0x31A7
    DRAW_TEXT 22, 48, 0xFFFF, 0x31A7, menu_terminal_label
    DRAW_TEXT 22, 88, 0xFFFF, 0x31A7, menu_shell_label
    DRAW_TEXT 22, 128, 0xFC50, 0x31A7, menu_shutdown_label
    DRAW_TEXT 22, 168, 0xFFFF, 0x31A7, menu_about_label
.done:
    ret

draw_desktop:
    cmp byte [graphics_ready], 1
    jne .text_desktop
    mov byte [mouse_cursor_drawn], 0
    call draw_graphical_desktop
    cmp byte [terminal_visible], 1
    jne .done
    call save_terminal_background
    call terminal_screen
.done:
    ret
.text_desktop:
    mov ax, 0x1F20
    mov edi, 0xB8000
    mov ecx, 2000
    rep stosw

    ; Top panel.
    mov ax, 0x7020
    mov edi, 0xB8000
    mov ecx, 80
    rep stosw
    WRITE_TEXT 0, 0x70, desktop_title
    cmp byte [fs_ready], 1
    jne .storage_offline
    WRITE_TEXT 56, 0x70, desktop_status
    jmp .storage_status_done
.storage_offline:
    WRITE_TEXT 56, 0x70, desktop_storage_offline
.storage_status_done:

    ; Quick-launch panel.
    WRITE_TEXT 242, 0x1E, launcher_border
    WRITE_TEXT 322, 0x1E, launcher_title
    WRITE_TEXT 402, 0x1F, launcher_terminal
    WRITE_TEXT 482, 0x1F, launcher_desktop
    WRITE_TEXT 562, 0x1A, launcher_shell
    WRITE_TEXT 642, 0x1F, launcher_blank
    WRITE_TEXT 722, 0x1E, launcher_files
    WRITE_TEXT 802, 0x1F, launcher_ls
    WRITE_TEXT 882, 0x1F, launcher_cat
    WRITE_TEXT 962, 0x1E, launcher_border

    ; Main welcome panel.
    WRITE_TEXT 348, 0x1F, window_border
    WRITE_TEXT 428, 0x1A, window_title
    WRITE_TEXT 508, 0x1F, window_blank
    WRITE_TEXT 588, 0x1F, desktop_welcome
    WRITE_TEXT 668, 0x1F, desktop_hint
    WRITE_TEXT 748, 0x1F, window_blank
    WRITE_TEXT 828, 0x1F, desktop_terminal_hint
    WRITE_TEXT 908, 0x1A, desktop_shell_hint
    WRITE_TEXT 988, 0x1F, desktop_desktop_hint
    WRITE_TEXT 1068, 0x1F, window_blank
    WRITE_TEXT 1148, 0x1F, desktop_program_hint
    WRITE_TEXT 1228, 0x1F, desktop_files_hint
    WRITE_TEXT 1308, 0x1F, window_border

    ; Bottom panel.
    mov ax, 0x7020
    mov edi, 0xB87A0
    mov ecx, 80
    rep stosw
    WRITE_TEXT 1920, 0x70, taskbar_label
    WRITE_TEXT 1991, 0x70, taskbar_vga
    ret

%include "shell/shell.asm"

draw_graphics_text_cell:
    cmp byte [graphics_ready], 1
    jne .done
    mov eax, [text_cell]
    xor edx, edx
    mov ecx, 80
    div ecx
    cmp byte [graphics_text_window], 1
    jne .desktop_cell
    shl eax, 4
    add eax, [terminal_window_y]
    add eax, 48
    mov esi, eax
    shl edx, 3
    add edx, [terminal_window_x]
    add edx, 24
    mov edi, edx
    jmp .draw_cell
.desktop_cell:
    mov esi, eax
    shl esi, 4
    mov edi, edx
    shl edi, 3
.draw_cell:
    movzx ecx, byte [text_character]
    movzx eax, byte [text_attr]
    mov ebx, eax
    and eax, 0x0F
    movzx edx, word [vga_palette + rax * 2]
    shr ebx, 4
    movzx r8d, word [vga_palette + rbx * 2]
    call draw_glyph
.done:
    ret

write_text:
    mov [text_ptr], rsi
.next_char:
    mov rsi, [text_ptr]
    lodsb
    mov [text_ptr], rsi
    test al, al
    jz .done
    cmp edi, 2000
    jae .done
    mov [text_character], al
    mov [text_cell], edi
    mov ah, [text_attr]
    mov [0xB8000 + rdi * 2], ax
    cmp byte [graphics_ready], 1
    jne .advance_cell
    call draw_graphics_text_cell
    mov edi, [text_cell]
.advance_cell:
    inc edi
    jmp .next_char
.done:
    ret

desktop_title db " FOXOS  |  DESKTOP", 0
desktop_status db "FOXFS READY", 0
desktop_storage_offline db "FOXFS OFFLINE", 0
desktop_apps db "Applications", 0
menu_terminal_label db "Terminal", 0
menu_shell_label db "C Shell", 0
menu_shutdown_label db "Shutdown", 0
menu_about_label db "About", 0
panel_terminal db "F1", 0
panel_shell db "F3", 0
panel_files db "F2", 0
panel_menu db "Applications", 0
icon_terminal db "Terminal", 0
icon_shell db "C Shell", 0
welcome_title db "Welcome to FoxOS", 0
desktop_welcome_graphical db "Welcome to your FoxOS desktop", 0
desktop_hint_graphical db "A lightweight graphical workspace for FoxOS.", 0
welcome_terminal db "Terminal", 0
welcome_shell db "C Shell", 0
welcome_storage db "FoxFS", 0
welcome_terminal_hint db "F1 or desktop shortcut", 0
welcome_shell_hint db "F3 or panel shortcut", 0
welcome_storage_hint db "Persistent disk storage", 0
welcome_about db "A small 64-bit operating system", 0
desktop_program_hint_graphical db "Run commands, browse FoxFS, and launch installed programs.", 0
desktop_files_hint_graphical db "Use ls, cat, cd, and pwd in the C shell to explore files.", 0
launcher_border db "+----------------------+", 0
launcher_title db "| FOXOS LAUNCHER       |", 0
launcher_terminal db "| F1  Terminal         |", 0
launcher_desktop db "| F2  Desktop          |", 0
launcher_shell db "| F3  C Shell          |", 0
launcher_blank db "|                      |", 0
launcher_files db "| FILES                |", 0
launcher_ls db "| ls /                 |", 0
launcher_cat db "| cat <file>           |", 0
window_border db "+--------------------------------------------------+", 0
window_blank db "|                                                  |", 0
window_title db "|                 WELCOME TO FOXOS                 |", 0
desktop_welcome db "|   A small 64-bit operating system built in       |", 0
desktop_hint db "|   assembly, with a C shell and persistent disk.  |", 0
desktop_terminal_hint db "|   Press F1 to open the terminal window.          |", 0
desktop_shell_hint db "|   Press F3 to open the interactive C shell.      |", 0
desktop_desktop_hint db "|   Press F2 to return to this desktop.            |", 0
desktop_program_hint db "|   Programs can run from initramfs or FoxFS.      |", 0
desktop_files_hint db "|   Use ls and cat in the C shell to explore.      |", 0
taskbar_label db " FOXOS  |  F1 TERMINAL  |  F2 DESKTOP  |  F3 C SHELL", 0
taskbar_resolution db "1024x768 VESA", 0
taskbar_vga db "80x25 VGA", 0
shell_window_title db " FOXOS C SHELL", 0
terminal_close_label db "X", 0

align 8
tss:
    times 104 db 0
idt_pointer:
    dw 4096 - 1
    dq idt
idt:
    times 256 * 16 db 0
user_cursor dq 1200
timer_ticks dq 0
framebuffer_address dq 0
framebuffer_pitch dd 0
framebuffer_width dd 0
framebuffer_height dd 0
graphics_ready db 0
mouse_event db 0
mouse_click db 0
mouse_packet_index db 0
mouse_buttons db 0
mouse_packet times 3 db 0
mouse_x dd 0
mouse_y dd 0
mouse_cursor_x dd 0
mouse_cursor_y dd 0
mouse_cursor_drawn db 0
mouse_cursor_widths db 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4
align 2
mouse_cursor_saved times 96 dw 0
terminal_window_x dd 280
terminal_window_y dd 100
terminal_drag_mouse_x dd 0
terminal_drag_mouse_y dd 0
terminal_visible db 0
terminal_drag db 0
applications_menu_open db 0
welcome_visible db 0
graphics_text_window db 0
terminal_rendering db 0
text_cell dd 0
text_character db 0
keyboard_head dd 0
keyboard_tail dd 0
keyboard_buffer times 256 db 0
align 8
fd_table times PROCESS_COUNT * FD_COUNT * FD_ENTRY_SIZE db 0
pipe_table times PIPE_COUNT * PIPE_SIZE db 0
user_entry dq 0x400000
elf_file dq 0
elf_size dq 0
elf_load_count db 0
elf_entry_found db 0
process_kind db 0
shell_name db "shell", 0
align 8
current_process dd 0
next_process_id dq 1
process_table times PROCESS_COUNT * PROCESS_SIZE db 0
shift_down db 0
exec_argc dq 0
exec_data_size dq 0
exec_arg_data times 1024 db 0
exec_envc dq 0
exec_env_size dq 0
exec_env_data times 1024 db 0

align 8
text_ptr dq 0
text_attr db 0
vga_palette dw 0x0000, 0x0015, 0x0540, 0x0555
    dw 0xA800, 0xA815, 0xAAA0, 0xAD55
    dw 0x52AA, 0x52BF, 0x57EA, 0x57FF
    dw 0xFAAA, 0xFABF, 0xFFEA, 0xFFFF
align 8
fs_ready db 0
fs_missing_final db 0
fs_open_flags dq 0
fs_open_kind dq 0
fs_open_size dq 0
fs_stat_buffer dq 0
fs_parent_id dq 0
fs_path_cursor dq 0
fs_path_final db 0
fs_component_length db 0
fs_entry_pointer dq 0
fs_selected_index dd 0
fs_selected_type db 0
fs_alloc_start dd 0
fs_alloc_count dd 0
fs_scan_start dd 0
fs_scan_count dd 0
fs_old_start dd 0
fs_old_count dd 0
fs_new_start dd 0
fs_need_sectors dd 0
fs_io_entry dq 0
fs_io_fd dq 0
fs_io_user dq 0
fs_io_remaining dq 0
fs_io_total dq 0
fs_io_position dq 0
fs_io_size dq 0
fs_io_part dq 0
fs_io_sector_index dd 0
fs_io_sector_offset dd 0
fs_io_lba dd 0
fs_name_buffer times 21 db 0
fs_header_buffer times 512 db 0
fs_table times 4096 db 0
fs_bitmap times 512 db 0
fs_sector_buffer times 512 db 0
