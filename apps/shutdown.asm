; shutdown: request ACPI power-off, then halt if the platform ignores it.

app_shutdown_name db "shutdown", 0

app_shutdown_run:
    mov rsi, shutdown_output
    mov [output_ptr], rsi
    call terminal_screen

    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xB004
    out dx, ax
    jmp system_halt

shutdown_output db "Shutting down...", 0
