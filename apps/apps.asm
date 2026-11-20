; App command registration.
; Add an app module and an APP_COMMAND entry here to expose its command.

%include "apps/help.asm"
%include "apps/about.asm"
%include "apps/clear.asm"
%include "apps/gui.asm"
%include "apps/reboot.asm"
%include "apps/halt.asm"
%include "apps/shutdown.asm"
%include "apps/cshell.asm"

%macro APP_COMMAND 1
    dq app_%1_name, app_%1_run
%endmacro

app_registry:
    APP_COMMAND help
    APP_COMMAND about
    APP_COMMAND clear
    APP_COMMAND gui
    APP_COMMAND reboot
    APP_COMMAND halt
    APP_COMMAND shutdown
    APP_COMMAND cshell
    dq 0, 0
