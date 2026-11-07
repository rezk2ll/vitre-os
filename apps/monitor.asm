; Monitor: `top` takes the screen and shows uptime, memory and heap use as
; bars, and every task with its state and the timer ticks it has run,
; redrawn each second. q or Esc return to the shell.

MON_BAR    equ 40                   ; bar width in characters
MON_TITLE  equ 0x0088c0d0
MON_USED   equ 0x00a3be8c
MON_FREE   equ 0x004c566a
MON_PERIOD equ 1000                 ; timer ticks between redraws

; name: cmd_top
; in:   rdi = arguments (ignored)
; out:  the monitor ran until q or Esc; the screen is cleared
; clobbers: caller-saved
cmd_top:
    push rbx
    cmp byte [rel console_ready], 0
    je .no_screen
    lea rdi, [rel mon_con]
    xor esi, esi
    xor edx, edx
    mov rcx, [rel kernel_console + CON_COLS]
    mov r8, [rel kernel_console + CON_ROWS]
    call console_init
.redraw:
    call mon_draw
    mov rbx, [rel timer_ticks]
.wait:
    call kbd_poll
    jnz .key
    mov rax, [rel timer_ticks]
    sub rax, rbx
    cmp rax, MON_PERIOD
    jae .redraw
    call task_yield
    jmp .wait
.key:
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    jne .wait
.quit:
    call shell_clear_screen
    pop rbx
    ret
.no_screen:
    lea rdi, [rel br_msg_no_screen]
    call kputs
    pop rbx
    ret

; name: mon_draw
; in:   mon_con set up
; out:  every line of the monitor drawn over the last ones
; clobbers: caller-saved
mon_draw:
    push rbx
    push r12
    push r13
    mov qword [rel mon_con + CON_CX], 0
    mov qword [rel mon_con + CON_CY], 0
    mov edi, MON_TITLE
    lea rsi, [rel mon_msg_title]
    call mon_text
    call mon_eol
    call mon_eol
    lea rsi, [rel mon_msg_uptime]
    call mon_label
    mov rax, [rel timer_ticks]
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov rdi, rax
    call mon_dec
    lea rsi, [rel mon_msg_seconds]
    call mon_plain
    call mon_eol
    lea rsi, [rel mon_msg_memory]
    call mon_label
    mov rdi, [rel pmm_total_pages]
    mov rsi, rdi
    sub rdi, [rel pmm_free_pages]
    lea rdx, [rel mon_msg_pages]
    call mon_bar
    lea rsi, [rel mon_msg_heap]
    call mon_label
    mov rdi, [rel heap_total_bytes]
    mov rsi, rdi
    sub rdi, [rel heap_free_bytes]
    lea rdx, [rel mon_msg_bytes]
    call mon_bar
    call mon_eol
    mov edi, MON_TITLE
    lea rsi, [rel mon_msg_header]
    call mon_text
    call mon_eol
    lea rbx, [rel sched_tasks]
    xor r12d, r12d
.task:
    mov r13, [rbx + TASK_STATE]
    cmp r13, TASK_FREE
    je .next
    mov edi, ' '
    call mon_putc
    mov edi, r12d
    call mon_dec
    mov edi, 5
    call mon_pad
    lea rsi, [rbx + TASK_NAME]
    call mon_plain
    mov edi, 22
    call mon_pad
    lea rsi, [rel mon_msg_ready]
    cmp r13, TASK_READY
    je .state
    lea rsi, [rel mon_msg_paused]
    cmp r13, TASK_PAUSED
    je .state
    lea rsi, [rel mon_msg_dead]
.state:
    call mon_plain
    mov edi, 32
    call mon_pad
    mov rdi, [rbx + TASK_TICKS]
    call mon_dec
    call mon_eol
.next:
    add rbx, TASK_SIZE
    inc r12d
    cmp r12d, MAX_TASKS
    jb .task
.blank:                             ; clear what a longer list left, but never
    mov rax, [rel mon_con + CON_CY] ; wrap the last row, which would scroll
    inc rax
    cmp rax, [rel mon_con + CON_ROWS]
    jae .done
    call mon_eol
    jmp .blank
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: mon_bar
; in:   rdi = used, rsi = total, rdx = unit name
; out:  "[####....]  used of total unit" and the end of the line
; clobbers: caller-saved
mon_bar:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx                    ; '#' cells
    test r13, r13
    jz .open
    mov rax, r12
    mov ecx, MON_BAR
    mul rcx
    div r13
    mov rbx, rax
    test r12, r12
    jz .open
    test rbx, rbx
    jnz .open
    inc ebx                         ; any use shows as a cell
.open:
    mov edi, '['
    call mon_putc
    xor r15d, r15d
.cell:
    cmp r15d, MON_BAR
    jae .close
    mov edi, MON_USED
    mov esi, '#'
    cmp r15, rbx
    jb .draw
    mov edi, MON_FREE
    mov esi, '.'
.draw:
    mov [rel mon_con + CON_FG], rdi
    mov edi, esi
    call mon_putc
    inc r15d
    jmp .cell
.close:
    mov qword [rel mon_con + CON_FG], COLOR_FG
    lea rsi, [rel mon_msg_close]
    call mon_plain
    mov rdi, r12
    call mon_dec
    lea rsi, [rel mon_msg_of]
    call mon_plain
    mov rdi, r13
    call mon_dec
    mov edi, ' '
    call mon_putc
    mov rsi, r14
    call mon_plain
    call mon_eol
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: mon_label
; in:   rsi = label
; out:  " label" and the cursor at the value column
; clobbers: caller-saved
mon_label:
    sub rsp, 8
    mov edi, ' '
    mov [rsp], rsi
    call mon_putc
    mov rsi, [rsp]
    call mon_plain
    mov edi, 10
    call mon_pad
    add rsp, 8
    ret

; name: mon_text
; in:   edi = colour, rsi = string
; out:  the string in that colour, then the colour back to the default
; clobbers: caller-saved
mon_text:
    sub rsp, 8
    mov [rel mon_con + CON_FG], rdi
    call mon_plain
    mov qword [rel mon_con + CON_FG], COLOR_FG
    add rsp, 8
    ret

; name: mon_plain
; in:   rsi = string
; out:  the string at the cursor
; clobbers: caller-saved
mon_plain:
    lea rdi, [rel mon_con]
    jmp console_puts

; name: mon_putc
; in:   edi = character
; out:  the character at the cursor
; clobbers: caller-saved
mon_putc:
    mov esi, edi
    lea rdi, [rel mon_con]
    jmp console_putc

; name: mon_pad
; in:   edi = column
; out:  spaces up to that column
; clobbers: caller-saved
mon_pad:
    push rbx
    mov ebx, edi
.space:
    cmp [rel mon_con + CON_CX], rbx
    jae .ret
    mov edi, ' '
    call mon_putc
    jmp .space
.ret:
    pop rbx
    ret

; name: mon_eol
; in:   none
; out:  spaces to the end of the row, so the cursor wraps to the next one
; clobbers: caller-saved
mon_eol:
    sub rsp, 8
.space:
    mov edi, ' '
    call mon_putc
    cmp qword [rel mon_con + CON_CX], 0
    jne .space
    add rsp, 8
    ret

; name: mon_dec
; in:   rdi = unsigned value
; out:  the value in decimal at the cursor
; clobbers: caller-saved
mon_dec:
    sub rsp, 40
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rax, rdi
    mov ecx, 10
.digit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit
    call mon_plain
    add rsp, 40
    ret

mon_msg_title   db " Vitre monitor, q quits", 0
mon_msg_uptime  db "uptime", 0
mon_msg_seconds db " s", 0
mon_msg_memory  db "memory", 0
mon_msg_heap    db "heap", 0
mon_msg_pages   db "pages used", 0
mon_msg_bytes   db "bytes used", 0
mon_msg_close   db "]  ", 0
mon_msg_of      db " of ", 0
mon_msg_header  db " id   name             state     ticks", 0
mon_msg_ready   db "ready", 0
mon_msg_paused  db "paused", 0
mon_msg_dead    db "ended", 0

section .bss
alignb 8
mon_con resb CON_SIZE
section .text
