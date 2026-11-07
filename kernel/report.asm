; Log printers, the first patchable module. Written in the Vitre dialect
; (docs/DIALECT.md) so Forge can reassemble it.

; name: kput_dec
; in:   rdi = unsigned value, printed in decimal
; out:  none
; clobbers: rax, rcx, rdx, rdi, rsi
; patchable: yes
kput_dec:
    sub rsp, 40
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rax, rdi
    mov ecx, 10
.div:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .div
    mov rdi, rsi
    call kputs
    add rsp, 40
    ret

; name: fb_log_mode
; in:   fb_init succeeded
; out:  "[fb] WxH" on the log
; clobbers: caller-saved
; patchable: yes
fb_log_mode:
    sub rsp, 8
    lea rdi, [rel fb_msg_mode]
    call kputs
    mov rdi, [rel fb_width]
    call [rel jt_kput_dec]
    mov edi, 'x'
    call kputc
    mov rdi, [rel fb_height]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    add rsp, 8
    ret

fb_msg_mode db "[fb] ", 0

; name: pmm_log
; in:   none
; out:  E820 map and free memory on the log
; clobbers: caller-saved
; patchable: yes
pmm_log:
    push rbx
    push r12
    sub rsp, 8
    movzx r12d, word [BOOTINFO_E820_COUNT]
    mov rbx, BOOTINFO_E820
.entry:
    test r12d, r12d
    jz .summary
    lea rdi, [rel pmm_msg_e820]
    call kputs
    mov rdi, [rbx]
    call kput_hex
    mov edi, ' '
    call kputc
    mov rdi, [rbx + 8]
    call kput_hex
    lea rdi, [rel pmm_msg_type]
    call kputs
    mov edi, [rbx + 16]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    add rbx, 24
    dec r12d
    jmp .entry
.summary:
    lea rdi, [rel pmm_msg_free]
    call kputs
    mov rdi, [rel pmm_free_pages]
    call [rel jt_kput_dec]
    lea rdi, [rel pmm_msg_of]
    call kputs
    mov rdi, [rel pmm_total_pages]
    call [rel jt_kput_dec]
    lea rdi, [rel pmm_msg_pages]
    call kputs
    add rsp, 8
    pop r12
    pop rbx
    ret

pmm_msg_e820  db "[mem] e820 ", 0
pmm_msg_type  db " type ", 0
pmm_msg_free  db "[mem] free pages ", 0
pmm_msg_of    db " of ", 0
pmm_msg_pages db " usable", 10, 0

; name: sched_list
; in:   none
; out:  one "[task] id name state ticks" line per task on the log
; clobbers: caller-saved
; patchable: yes
sched_list:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [rel sched_tasks]
    xor r12d, r12d
.task:
    cmp qword [rbx + TASK_STATE], TASK_FREE
    je .next
    lea rdi, [rel sched_msg_task]
    call kputs
    mov edi, r12d
    call [rel jt_kput_dec]
    mov edi, ' '
    call kputc
    lea rdi, [rbx + TASK_NAME]
    call kputs
    lea rdi, [rel sched_msg_ready]
    cmp qword [rbx + TASK_STATE], TASK_READY
    je .state
    lea rdi, [rel sched_msg_paused]
    cmp qword [rbx + TASK_STATE], TASK_PAUSED
    je .state
    lea rdi, [rel sched_msg_dead]
.state:
    call kputs
    mov rdi, [rbx + TASK_TICKS]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
.next:
    add rbx, TASK_SIZE
    inc r12d
    cmp r12d, MAX_TASKS
    jb .task
    add rsp, 8
    pop r12
    pop rbx
    ret

sched_msg_task  db "[task] ", 0
sched_msg_ready db " ready ", 0
sched_msg_dead  db " dead ", 0
sched_msg_paused db " paused ", 0
