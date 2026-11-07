; Programs: `run <file> [arguments]` assembles a user file with Forge into
; fresh pages and calls its first line with rdi = the arguments. The program
; returns with ret, and it may call any kernel function by name. A trailing
; `&` runs it as its own task instead, its arguments copied to the end of
; its pages.

RUN_PAGES equ 16
RUN_ARGS  equ 256                   ; argument room of a background program

; name: cmd_run
; in:   rdi = path, then the arguments after a space
; out:  the program ran and returned, or why not on the log
; clobbers: caller-saved
cmd_run:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov rbx, rdi
    call run_background
    movzx ebp, al
    mov r12, rbx
.split:
    mov al, [r12]
    test al, al
    jz .split_done
    inc r12
    cmp al, ' '
    jne .split
    mov byte [r12 - 1], 0
.split_done:
    mov rdi, rbx
    call src_find
    jc .missing
    mov r13, rax
    mov r14, rdx
    mov edi, RUN_PAGES
    call page_alloc
    jc .no_memory
    mov r15, rax
    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    mov rcx, r15
    mov r8d, RUN_PAGES * PAGE_SIZE - RUN_ARGS
    call forge_assemble
    jc .error
    test ebp, ebp
    jnz .task
    add rax, r15
    mov [rel run_code], r15
    mov [rel run_code_end], rax
    mov rdi, r12
    call r15
    mov qword [rel run_code], 0
    mov qword [rel run_code_end], 0
    jmp .free
.task:
    mov rsi, r12
    lea rdi, [r15 + RUN_PAGES * PAGE_SIZE - RUN_ARGS]
    mov ecx, RUN_ARGS - 1
.copy:
    lodsb
    stosb
    test al, al
    loopnz .copy
    mov byte [rdi], 0
    pushfq
    cli                             ; the task must not end before it is listed
    lea rdi, [rel run_task]
    mov rsi, rbx
    mov rdx, r15
    call task_create
    jc .no_task
    lea rcx, [rel run_task_pages]
    mov [rcx + rax * 8], r15
    popfq
    mov r13, rax
    lea rdi, [rel run_msg_prefix]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel run_msg_task]
    call kputs
    mov rdi, r13
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    jmp .done
.no_task:
    popfq
    lea rdi, [rel forge_msg_no_memory]
    call kputs
    jmp .free
.error:
    lea rdi, [rel run_msg_prefix]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel forge_msg_colon]
    call kputs
    call forge_log_error
.free:
    mov rdi, r15
    mov esi, RUN_PAGES
    call page_free
    jmp .done
.missing:
    lea rdi, [rel files_msg_missing]
    call kputs
    mov rdi, rbx
    call kputs
    mov edi, 10
    call kputc
    jmp .done
.no_memory:
    lea rdi, [rel forge_msg_no_memory]
    call kputs
.done:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: run_background
; in:   rdi = arguments
; out:  al = 1 and the `&` cut off when they end with one, else al = 0
; clobbers: rax, rcx, rdi
run_background:
    mov rcx, rdi
.end:
    cmp byte [rdi], 0
    je .ends
    inc rdi
    jmp .end
.ends:
    cmp rdi, rcx
    je .no
    cmp byte [rdi - 1], '&'
    jne .no
    dec rdi
.trim:
    mov byte [rdi], 0
    cmp rdi, rcx
    je .yes
    cmp byte [rdi - 1], ' '
    jne .yes
    dec rdi
    jmp .trim
.yes:
    mov al, 1
    ret
.no:
    xor eax, eax
    ret

; name: run_task
; in:   rdi = the program's pages, its arguments at the end
; out:  the program ran as this task; its pages freed
; clobbers: caller-saved
run_task:
    push rbx
    mov rbx, rdi
    lea rdi, [rbx + RUN_PAGES * PAGE_SIZE - RUN_ARGS]
    call rbx
    cli
    mov eax, [rel sched_current]
    lea rcx, [rel run_task_pages]
    mov qword [rcx + rax * 8], 0
    sti
    mov rdi, rbx
    mov esi, RUN_PAGES
    call page_free
    pop rbx
    ret

; name: run_fault
; in:   rdi = frame of a CPU exception
; out:  rax = frame to resume when a program faulted: the shell's resume
;       point for a program the shell runs, the next task for a background
;       one, which ends. Its pages freed and the fault on the log. CF=1 and
;       rdi = the frame otherwise
; clobbers: caller-saved
run_fault:
    push rbx
    push rbp
    mov rbp, rsp
    and rsp, -16                    ; any stack depth
    mov rbx, rdi
    test qword [rbx + INT_FRAME_RFLAGS], 0x200  ; IF=0: inside an IRQ handler,
    jz .fatal                                   ; whose EOI would be lost
    mov eax, [rel sched_current]
    lea rcx, [rel run_task_pages]
    cmp qword [rcx + rax * 8], 0
    jne .report
    cmp qword [rel run_code], 0
    je .fatal
    cmp qword [rel shell_resume_rip], 0
    je .fatal
    cmp eax, [rel shell_resume_task]
    jne .fatal
.report:
    lea rdi, [rel run_msg_fault]
    call kputs
    mov rax, [rbx + INT_FRAME_VECTOR]
    lea rdi, [rel exc_names]
    lea rdi, [rdi + rax * 4]
    call kputs
    lea rdi, [rel run_msg_at]
    call kputs
    mov rdi, [rbx + INT_FRAME_RIP]
    call kput_hex
    lea rdi, [rel run_msg_stopped]
    call kputs
    mov eax, [rel sched_current]
    lea rcx, [rel run_task_pages]
    mov rdi, [rcx + rax * 8]
    test rdi, rdi
    jz .foreground
    mov qword [rcx + rax * 8], 0
    imul eax, TASK_SIZE
    lea rcx, [rel sched_tasks]
    mov qword [rcx + rax + TASK_STATE], TASK_DEAD
    mov esi, RUN_PAGES
    call page_free
    mov rdi, rbx
    call sched_switch
    clc
    jmp .return
.foreground:
    mov rdi, rbx
    call run_stop
    clc
    jmp .return
.fatal:
    mov rdi, rbx
    stc
.return:
    mov rsp, rbp
    pop rbp
    pop rbx
    ret

; name: run_poll
; in:   rdi = frame of an IRQ
; out:  rax = frame to resume. When Ctrl+C is the newest key and the IRQ
;       interrupted the running program's own code, the key is taken and
;       the program stopped; otherwise the frame is rdi, untouched
; clobbers: caller-saved
run_poll:
    mov rax, rdi
    mov rcx, [rel run_code]
    test rcx, rcx
    jz .done
    mov rdx, [rdi + INT_FRAME_RIP]
    cmp rdx, rcx
    jb .done
    cmp rdx, [rel run_code_end]
    jae .done
    cmp qword [rel shell_resume_rip], 0
    je .done
    mov edx, [rel sched_current]
    cmp edx, [rel shell_resume_task]
    jne .done
    mov ecx, [rel kbd_head]
    cmp ecx, [rel kbd_tail]
    je .done
    dec ecx
    and ecx, KBD_BUF_SIZE - 1
    lea rdx, [rel kbd_buf]
    cmp byte [rdx + rcx], 3         ; Ctrl+C
    jne .done
    mov [rel kbd_head], ecx
    push rdi
    lea rdi, [rel run_msg_break]
    call kputs
    pop rdi
    jmp run_stop
.done:
    ret

; name: run_stop
; in:   rdi = frame the running program was stopped in
; out:  rax = that frame, set to resume the shell after `run`; the
;       program's pages freed
; clobbers: caller-saved
run_stop:
    push rdi
    mov rdi, [rel run_code]
    mov esi, RUN_PAGES
    call page_free
    pop rdx
    xor eax, eax
    mov [rel run_code], rax
    mov [rel run_code_end], rax
    mov rax, [rel shell_resume_rip]
    mov [rdx + INT_FRAME_RIP], rax
    mov rax, [rel shell_resume_rsp]
    mov [rdx + INT_FRAME_RSP], rax
    mov rax, rdx
    ret

run_msg_prefix  db "[run] ", 0
run_msg_fault   db 10, "[run] #", 0
run_msg_at      db " at ", 0
run_msg_stopped db ", program stopped", 10, 0
run_msg_break   db "^C", 10, "[run] Ctrl+C, program stopped", 10, 0
run_msg_task    db " is task ", 0

section .bss
alignb 8
run_code     resq 1                 ; the running program, 0 when none
run_code_end resq 1
run_task_pages resq MAX_TASKS       ; a background program's pages by task id
section .text
