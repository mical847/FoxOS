; cshell: start the interactive C shell in user mode.

app_cshell_name db "cshell", 0

app_cshell_run:
    jmp launch_c_shell
