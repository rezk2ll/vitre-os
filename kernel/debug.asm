; Task debugging: pause, resume and single-step other tasks. A paused task
; keeps its saved frame and is skipped by the scheduler; a step sets the
; trap flag in that frame, lets the task run one instruction, and the #DB
; it raises pauses it again.

DEBUG_VECTOR equ 1
RFLAGS_TF    equ 0x100

; name: debug_init
; in:   idt_init done
; out:  #DB handled by the single-step trap
; clobbers: rax, rdi, rsi
debug_init:
    mov edi, DEBUG_VECTOR
    lea rsi, [rel debug_trap]
    jmp isr_set_handler

; name: task_entry
; in:   edi = task id
; out:  rax = its task table entry; CF=1 for task 0, a free slot or an id
;       out of range
; clobbers: rax
task_entry:
    test edi, edi
    jz .bad
    cmp edi, MAX_TASKS
    jae .bad
    mov eax, edi
    imul eax, TASK_SIZE
    push rcx
    lea rcx, [rel sched_tasks]
    add rax, rcx
    pop rcx
    cmp qword [rax + TASK_STATE], TASK_READY
    je .ok
    cmp qword [rax + TASK_STATE], TASK_PAUSED
    jne .bad
.ok:
    clc
    ret
.bad:
    stc
    ret

; name: task_pause
; in:   edi = task id
; out:  task paused; CF=1 if it is not a ready task
; clobbers: rax, rcx, rdx
task_pause:
    mov ecx, TASK_READY
    mov edx, TASK_PAUSED
    jmp task_move

; name: task_resume
; in:   edi = task id
; out:  task ready again; CF=1 if it is not paused
; clobbers: rax, rcx, rdx
task_resume:
    mov ecx, TASK_PAUSED
    mov edx, TASK_READY

; name: task_move
; in:   edi = task id, rcx = state it must be in, rdx = state to set
; out:  state set; CF=1 if the task is not in state rcx
; clobbers: rax
task_move:
    call task_entry
    jc .done
    cmp [rax + TASK_STATE], rcx
    jne .bad
    mov [rax + TASK_STATE], rdx
    clc
.done:
    ret
.bad:
    stc
    ret

; name: task_step
; in:   edi = task id
; out:  the paused task has run one instruction and is paused again,
;       rax = its new RIP; CF=1 if it is not paused or did not stop
; clobbers: caller-saved
task_step:
    push rbx
    call task_entry
    jc .done
    mov rbx, rax
    cmp qword [rbx + TASK_STATE], TASK_PAUSED
    jne .bad
    pushfq
    cli
    mov rax, [rbx + TASK_FRAME]
    or qword [rax + INT_FRAME_RFLAGS], RFLAGS_TF
    mov [rel debug_step_task], edi
    mov qword [rbx + TASK_STATE], TASK_READY
    popfq
    mov rcx, [rel timer_ticks]
    add rcx, 1000
    mov [rel debug_step_deadline], rcx
.wait:
    call task_yield
    cmp qword [rbx + TASK_STATE], TASK_PAUSED
    je .stopped
    mov rcx, [rel timer_ticks]
    cmp rcx, [rel debug_step_deadline]
    jb .wait
    pushfq                          ; never trapped: take the step back
    cli
    mov dword [rel debug_step_task], 0
    mov rax, [rbx + TASK_FRAME]
    and qword [rax + INT_FRAME_RFLAGS], ~RFLAGS_TF
    mov qword [rbx + TASK_STATE], TASK_PAUSED
    popfq
    jmp .bad
.stopped:
    mov rax, [rbx + TASK_FRAME]
    mov rax, [rax + INT_FRAME_RIP]
    clc
.done:
    pop rbx
    ret
.bad:
    stc
    pop rbx
    ret

; name: debug_trap
; in:   rdi = frame of the task that raised #DB
; out:  rax = frame to resume: the stepped task is paused and another runs;
;       any other #DB is fatal
; clobbers: caller-saved
debug_trap:
    mov eax, [rel sched_current]
    test eax, eax
    jz isr_default
    cmp eax, [rel debug_step_task]
    jne isr_default
    and qword [rdi + INT_FRAME_RFLAGS], ~RFLAGS_TF
    mov dword [rel debug_step_task], 0
    imul eax, TASK_SIZE
    lea rcx, [rel sched_tasks]
    mov qword [rcx + rax + TASK_STATE], TASK_PAUSED
    jmp sched_switch

section .bss
alignb 8
debug_step_deadline resq 1
debug_step_task     resd 1
section .text
