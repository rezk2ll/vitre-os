; Shell commands that control tasks: start a spinning task, pause, resume
; and single-step one.

; name: parse_dec
; in:   rdi = string
; out:  rax = its decimal value; CF=1 if it is empty or not all digits
; clobbers: rcx, rdi
parse_dec:
    xor eax, eax
    cmp byte [rdi], 0
    je .bad
.digit:
    movzx ecx, byte [rdi]
    test ecx, ecx
    jz .ok
    sub ecx, '0'
    cmp ecx, 9
    ja .bad
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp .digit
.ok:
    clc
    ret
.bad:
    stc
    ret

; name: parse_addr
; in:   rdi = 0x and a hex number, or a kernel label
; out:  rax = address; CF=1 if it is neither
; clobbers: rcx, rdx, rdi, rsi
parse_addr:
    cmp word [rdi], "0x"
    jne lab_lookup
    add rdi, 2
    xor eax, eax
    xor edx, edx                    ; digits read
.digit:
    movzx ecx, byte [rdi]
    test ecx, ecx
    jz .end
    sub ecx, '0'
    cmp ecx, 9
    jbe .add
    add ecx, '0'
    or ecx, 0x20                    ; lower case
    sub ecx, 'a'
    cmp ecx, 5
    ja .bad
    add ecx, 10
.add:
    shl rax, 4
    add rax, rcx
    inc rdi
    inc edx
    cmp edx, 16
    ja .bad
    jmp .digit
.end:
    test edx, edx
    jz .bad
    clc
    ret
.bad:
    stc
    ret

; name: spin_task
; in:   none
; out:  never returns: counts in a tight loop, a target for `step`
spin_task:
.loop:
    inc qword [rel spin_count]
    jmp .loop

; name: cmd_spin
; in:   rdi = arguments (ignored)
; out:  a spin task started, its id printed
; clobbers: caller-saved
cmd_spin:
    push rbx
    lea rdi, [rel spin_task]
    lea rsi, [rel taskcmd_spin]
    xor edx, edx
    call task_create
    jc .fail
    mov rbx, rax
    lea rdi, [rel taskcmd_msg_spin]
    call kputs
    mov rdi, rbx
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    pop rbx
    ret
.fail:
    lea rdi, [rel taskcmd_msg_no_task]
    call kputs
    pop rbx
    ret

; name: cmd_pause
; in:   rdi = task id
; out:  task paused, or an error printed
; clobbers: caller-saved
cmd_pause:
    lea rsi, [rel task_pause]
    lea rdx, [rel taskcmd_msg_paused]
    jmp taskcmd_run

; name: cmd_resume
; in:   rdi = task id
; out:  task running again, or an error printed
; clobbers: caller-saved
cmd_resume:
    lea rsi, [rel task_resume]
    lea rdx, [rel taskcmd_msg_resumed]
    jmp taskcmd_run

; name: cmd_step
; in:   rdi = task id
; out:  the paused task ran one instruction; "[step] task N rip <hex>"
; clobbers: caller-saved
cmd_step:
    lea rsi, [rel task_step]
    lea rdx, [rel taskcmd_msg_rip]
    jmp taskcmd_run

; name: taskcmd_run
; in:   rdi = task id string, rsi = operation (edi = id, CF on failure,
;       rax = RIP for a step), rdx = message after "task N"
; out:  "[task] task N <message>" (the RIP after a step), or an error
; clobbers: caller-saved
taskcmd_run:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    call parse_dec
    jc .usage
    cmp rax, MAX_TASKS
    jae .refused
    mov rbx, rax
    mov edi, ebx
    call r12
    jc .refused
    mov r12, rax
    lea rdi, [rel taskcmd_msg_prefix]
    call kputs
    mov rdi, rbx
    call [rel jt_kput_dec]
    mov rdi, r13
    call kputs
    lea rax, [rel taskcmd_msg_rip]
    cmp r13, rax
    jne .newline
    mov rdi, r12
    call kput_hex
.newline:
    mov edi, 10
    call kputc
    jmp .done
.usage:
    lea rdi, [rel taskcmd_msg_usage]
    call kputs
    jmp .done
.refused:
    lea rdi, [rel taskcmd_msg_refused]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

taskcmd_spin        db "spin", 0
taskcmd_msg_spin    db "[task] started spin, task ", 0
taskcmd_msg_no_task db "[task] no free task slot", 10, 0
taskcmd_msg_prefix  db "[task] task ", 0
taskcmd_msg_paused  db " paused", 0
taskcmd_msg_resumed db " resumed", 0
taskcmd_msg_rip     db " rip ", 0
taskcmd_msg_usage   db "usage: pause|resume|step <task id>", 10, 0
taskcmd_msg_refused db "[task] not a task in that state", 10, 0

section .bss
alignb 8
spin_count resq 1
section .text
