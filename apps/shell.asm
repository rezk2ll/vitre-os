; Shell: reads a line from the keyboard, runs the command it names.

SHELL_LINE_MAX equ 1024

SHELL_NAME_COLUMN equ 10

; A command record is its handler (rdi = argument string), then its name and
; its summary as zero-terminated strings. A zero handler ends the table.
%macro shell_command 3
    dq %2
    db %1, 0, %3, 0
%endmacro

; name: shell_run
; in:   keyboard and console ready, interrupts on
; out:  does not return
; clobbers: everything
shell_run:
    sub rsp, 8
    lea rdi, [rel shell_msg_ready]
    call kputs
    lea rdi, [rel shell_opt_desktop]
    call cmdline_has
    jnz .line
    call cmd_desktop
.line:
    lea rdi, [rel shell_prompt]
    call kputs
    lea rdi, [rel shell_line]
    call shell_readline
    lea rdi, [rel shell_line]
    call shell_execute
    jmp .line

; name: shell_readline
; in:   rdi = buffer of SHELL_LINE_MAX bytes
; out:  zero-terminated line in the buffer, rax = length; the line is echoed.
;       Backspace erases, Ctrl+C drops the line, Ctrl+L clears the screen;
;       PgUp, PgDn and the wheel scroll back through earlier output.
; clobbers: caller-saved
shell_readline:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    xor r12d, r12d
.key:
    call sb_getc
    cmp eax, 10
    je .enter
    cmp eax, 8
    je .backspace
    cmp eax, 3
    je .cancel
    cmp eax, 12
    je .clear
    cmp eax, ' '
    jb .key
    lea ecx, [rax - 0x80]           ; KEY_* codes have no character
    cmp ecx, 0x20
    jb .key
    cmp r12d, SHELL_LINE_MAX - 1
    jae .key
    mov [rbx + r12], al
    inc r12d
    mov edi, eax
    call kputc
    jmp .key
.backspace:
    test r12d, r12d
    jz .key
    dec r12d
    mov edi, 8
    call kputc
    jmp .key
.cancel:
    lea rdi, [rel shell_msg_cancel]
    call kputs
    xor r12d, r12d
    jmp .enter
.clear:
    call shell_clear_screen
    lea rdi, [rel shell_prompt]
    call kputs
    mov byte [rbx + r12], 0
    mov rdi, rbx
    call kputs
    jmp .key
.enter:
    mov byte [rbx + r12], 0
    mov edi, 10
    call kputc
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: shell_execute
; in:   rdi = command line (modified: the command word is cut off with a 0)
; out:  the command has run, or "unknown command" was printed
; clobbers: caller-saved
shell_execute:
    push rbx
    push r12
    push r13
    mov rbx, rdi
.skip_lead:
    cmp byte [rbx], ' '
    jne .word
    inc rbx
    jmp .skip_lead
.word:
    cmp byte [rbx], 0
    je .done
    mov r12, rbx                    ; r12 = argument string
.scan:
    mov al, [r12]
    test al, al
    jz .args
    cmp al, ' '
    je .cut
    inc r12
    jmp .scan
.cut:
    mov byte [r12], 0
    inc r12
.skip_space:
    cmp byte [r12], ' '
    jne .args
    inc r12
    jmp .skip_space
.args:
    lea r13, [rel shell_commands]
.find:
    cmp qword [r13], 0
    je .unknown
    mov rdi, rbx
    lea rsi, [r13 + 8]
    call str_eq
    je .run
    mov rdi, r13
    call shell_next_command
    mov r13, rax
    jmp .find
.run:
    lea rax, [rel .returned]        ; where patch_fault resumes the shell
    mov [rel shell_resume_rip], rax
    mov [rel shell_resume_rsp], rsp
    mov eax, [rel sched_current]
    mov [rel shell_resume_task], eax
    mov rdi, r12
    call [r13]
.returned:
    mov qword [rel shell_resume_rip], 0
    jmp .done
.unknown:
    lea rdi, [rel shell_msg_unknown]
    call kputs
    mov rdi, rbx
    call kputs
    mov edi, 10
    call kputc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: shell_clear_screen
; in:   none
; out:  console cleared, cursor at the top left
; clobbers: caller-saved
shell_clear_screen:
    cmp byte [rel console_ready], 0
    je .done
    lea rdi, [rel kernel_console]
    jmp console_clear
.done:
    ret

; name: cmd_help
; in:   rdi = arguments (ignored)
; out:  one line per command with its summary
; clobbers: caller-saved
cmd_help:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [rel shell_commands]
.next:
    cmp qword [rbx], 0
    je .done
    lea rdi, [rel shell_indent]
    call kputs
    lea r12, [rbx + 8]
.name:
    movzx edi, byte [r12]
    inc r12
    test edi, edi
    jz .pad
    call kputc
    jmp .name
.pad:
    lea rax, [rbx + 8 + SHELL_NAME_COLUMN]
    cmp r12, rax
    ja .summary
    mov edi, ' '
    call kputc
    inc r12
    jmp .pad
.summary:
    lea rdi, [rbx + 8]
    call str_skip
    mov rdi, rax
    call kputs
    mov edi, 10
    call kputc
    mov rdi, rbx
    call shell_next_command
    mov rbx, rax
    jmp .next
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: shell_next_command
; in:   rdi = command record
; out:  rax = the record after it
; clobbers: rdi
shell_next_command:
    lea rdi, [rdi + 8]
    call str_skip
    mov rdi, rax
    jmp str_skip

; name: cmd_mem
; in:   rdi = arguments (ignored)
; out:  free and total physical pages and heap bytes
; clobbers: caller-saved
cmd_mem:
    sub rsp, 8
    lea rdi, [rel shell_msg_pages]
    call kputs
    mov rdi, [rel pmm_free_pages]
    call [rel jt_kput_dec]
    lea rdi, [rel shell_msg_of]
    call kputs
    mov rdi, [rel pmm_total_pages]
    call [rel jt_kput_dec]
    lea rdi, [rel shell_msg_heap]
    call kputs
    mov rdi, [rel heap_free_bytes]
    call [rel jt_kput_dec]
    lea rdi, [rel shell_msg_of]
    call kputs
    mov rdi, [rel heap_total_bytes]
    call [rel jt_kput_dec]
    lea rdi, [rel shell_msg_bytes]
    call kputs
    add rsp, 8
    ret

; name: cmd_uptime
; in:   rdi = arguments (ignored)
; out:  seconds and milliseconds since the PIT started
; clobbers: caller-saved
cmd_uptime:
    push rbx
    lea rdi, [rel shell_msg_up]
    call kputs
    mov rax, [rel timer_ticks]
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov rbx, rdx
    mov rdi, rax
    call [rel jt_kput_dec]
    mov edi, '.'
    call kputc
    mov rax, rbx                    ; three digits of milliseconds
    mov ecx, 100
    xor edx, edx
    div ecx
    mov rbx, rdx
    lea edi, [rax + '0']
    call kputc
    mov eax, ebx
    mov ecx, 10
    xor edx, edx
    div ecx
    mov ebx, edx
    lea edi, [rax + '0']
    call kputc
    lea edi, [rbx + '0']
    call kputc
    lea rdi, [rel shell_msg_seconds]
    call kputs
    pop rbx
    ret

; name: cmd_layout
; in:   rdi = "azerty", "qwerty" or empty
; out:  keyboard layout switched, or the current one printed
; clobbers: caller-saved
cmd_layout:
    push rbx
    mov rbx, rdi
    cmp byte [rbx], 0
    je .show
    lea rsi, [rel shell_azerty]
    call str_eq
    jne .not_azerty
    mov byte [rel kbd_layout], KBD_LAYOUT_AZERTY
    jmp .show
.not_azerty:
    mov rdi, rbx
    lea rsi, [rel shell_qwerty]
    call str_eq
    jne .usage
    mov byte [rel kbd_layout], KBD_LAYOUT_QWERTY
.show:
    lea rdi, [rel shell_msg_layout]
    call kputs
    lea rdi, [rel shell_azerty]
    cmp byte [rel kbd_layout], KBD_LAYOUT_QWERTY
    jne .print
    lea rdi, [rel shell_qwerty]
.print:
    call kputs
    mov edi, 10
    call kputc
    pop rbx
    ret
.usage:
    lea rdi, [rel shell_msg_layout_usage]
    call kputs
    pop rbx
    ret

; name: cmd_reboot
; in:   rdi = arguments (ignored)
; out:  does not return: pulses the 8042 reset line, then triple faults
; clobbers: everything
cmd_reboot:
    lea rdi, [rel shell_msg_reboot]
    call kputs
    cli
.wait:
    in al, 0x64
    test al, 2
    jnz .wait
    mov al, 0xfe
    out 0x64, al
    lidt [rel shell_null_idt]       ; still here: any interrupt now triple faults
    int3

; name: cmd_shutdown
; in:   rdi = arguments (ignored)
; out:  does not return: the machine powers off through ACPI
; clobbers: everything
cmd_shutdown:
    lea rdi, [rel shell_msg_shutdown]
    call kputs
    cli
    ; PM1a control with SLP_EN: QEMU's PIIX4 and Q35, then older Bochs
    ; and VirtualBox, which put it elsewhere
    mov ax, 0x2000
    mov dx, 0x604
    out dx, ax
    mov dx, 0xb004
    out dx, ax
    mov ax, 0x3400
    mov dx, 0x4004
    out dx, ax
    lea rdi, [rel shell_msg_off]
    call kputs
.halt:
    hlt
    jmp .halt

; name: cmd_tasks
; in:   rdi = arguments (ignored)
; out:  the task table
; clobbers: caller-saved
cmd_tasks:
    jmp [rel jt_sched_list]

shell_commands:
    shell_command "help", cmd_help, "list commands"
    shell_command "clear", shell_clear_screen, "clear the screen (also Ctrl+L)"
    shell_command "mem", cmd_mem, "free pages and heap"
    shell_command "tasks", cmd_tasks, "list tasks"
    shell_command "top", cmd_top, "watch memory and tasks live"
    shell_command "spin", cmd_spin, "start a task that counts forever"
    shell_command "pause", cmd_pause, "pause a task: pause <id>"
    shell_command "resume", cmd_resume, "resume a paused task: resume <id>"
    shell_command "step", cmd_step, "run one instruction of a paused task"
    shell_command "dis", cmd_dis, "disassemble: dis <0xaddr|label> [count]"
    shell_command "glass", cmd_glass, "watch a task live: glass [task id] [0xaddr|label], or glass patch"
    shell_command "break", cmd_break, "pause the task that runs it: break <0xaddr|label>"
    shell_command "syms", sym_dump, "dump the symbol table"
    shell_command "lspci", cmd_lspci, "list PCI devices"
    shell_command "net", cmd_net, "network card, link and frame counters"
    shell_command "arp", cmd_arp, "resolve an address: arp [a.b.c.d], or list the cache"
    shell_command "ping", cmd_ping, "send 4 echo requests: ping a.b.c.d|name"
    shell_command "dhcp", cmd_dhcp, "ask for a new address lease"
    shell_command "host", cmd_host, "look up a name: host example.com"
    shell_command "tcp", cmd_tcp, "open and close a connection: tcp host port"
    shell_command "get", cmd_get, "fetch a page and print it raw: get http://host/path"
    shell_command "view", cmd_view, "fetch a page and print it as text: view http://host/path"
    shell_command "browse", cmd_browse, "open the browser: browse [http://host/path]"
    shell_command "tls", cmd_tls, "try a TLS 1.3 handshake: tls <host> <port>"
    shell_command "trust", cmd_trust, "trust a CA's P-256 key: trust <x y in hex>"
    shell_command "crypto", cmd_crypto, "run a primitive on hex input: crypto sha256|hmac|hkdf|chacha20|poly1305|seal|open|x25519|label|pmul|ninv|ecmul|ecdsa|x509|x509host <hex>..."
    shell_command "forge", forge_check, "reassemble the patchable modules"
    shell_command "edit", cmd_edit, "edit a module: edit <module>"
    shell_command "patch", cmd_patch, "patch a module live: patch <module>"
    shell_command "rollback", cmd_rollback, "undo the last patch"
    shell_command "save", cmd_save, "write edited modules to disk"
    shell_command "uptime", cmd_uptime, "time since boot"
    shell_command "date", cmd_date, "the date and time, UTC"
    shell_command "layout", cmd_layout, "keyboard layout: layout [azerty|qwerty]"
    shell_command "mouse", cmd_mouse, "the mouse position and buttons"
    shell_command "reboot", cmd_reboot, "restart the machine"
    shell_command "shutdown", cmd_shutdown, "power the machine off"
    shell_command "desktop", cmd_desktop, "the desktop: click an app to open it"
    dq 0

shell_null_idt dw 0
               dq 0

shell_msg_ready  db "[shell] ready, type help", 10, 0
shell_prompt     db "vitre> ", 0
shell_msg_cancel db "^C", 0
shell_msg_unknown db "unknown command: ", 0
shell_indent     db "  ", 0
shell_msg_pages  db "pages free ", 0
shell_msg_of     db " of ", 0
shell_msg_heap   db ", heap free ", 0
shell_msg_bytes  db " bytes", 10, 0
shell_msg_up     db "up ", 0
shell_msg_seconds db " s", 10, 0
shell_msg_layout db "layout ", 0
shell_msg_layout_usage db "usage: layout [azerty|qwerty]", 10, 0
shell_azerty     db "azerty", 0
shell_qwerty     db "qwerty", 0
shell_msg_reboot db "[shell] rebooting", 10, 0
shell_opt_desktop db "desktop", 0
shell_msg_shutdown db "[shell] powering off", 10, 0
shell_msg_off    db "[shell] no ACPI power-off here; safe to switch off", 10, 0

section .bss
shell_line resb SHELL_LINE_MAX
section .text
