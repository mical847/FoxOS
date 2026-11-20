; gui: return to the desktop.

app_gui_name db "gui", 0

app_gui_run:
    mov byte [screen_mode], 0
    mov byte [terminal_visible], 0
    mov byte [terminal_drag], 0
    call draw_desktop
    ret
