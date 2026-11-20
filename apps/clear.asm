; clear: clear the previous command and terminal output.

app_clear_name db "clear", 0

app_clear_run:
    mov rsi, empty_output
    mov [output_ptr], rsi
    mov rdi, last_command
    xor eax, eax
    mov ecx, 40
    rep stosb
    ret

empty_output db 0
