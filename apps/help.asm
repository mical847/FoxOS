; help: list registered shell commands.

app_help_name db "help", 0

app_help_run:
    mov rsi, help_output
    mov [output_ptr], rsi
    ret

help_output db "help about clear gui reboot halt shutdown", 0
