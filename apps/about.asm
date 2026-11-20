; about: show basic FoxOS information.

app_about_name db "about", 0

app_about_run:
    mov rsi, about_output
    mov [output_ptr], rsi
    ret

about_output db "FoxOS: NASM-only 64-bit assembly OS.", 0
