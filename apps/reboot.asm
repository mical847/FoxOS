; reboot: request a keyboard-controller reset.

app_reboot_name db "reboot", 0

app_reboot_run:
    mov rsi, reboot_output
    mov [output_ptr], rsi
    call terminal_screen
    mov al, 0xFE
    out 0x64, al
    jmp system_halt

reboot_output db "Rebooting...", 0
