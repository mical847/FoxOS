; halt: stop the CPU.

app_halt_name db "halt", 0

app_halt_run:
    mov rsi, halt_output
    mov [output_ptr], rsi
    call terminal_screen
    jmp system_halt

halt_output db "System halted.", 0
