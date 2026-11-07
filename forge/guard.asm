; Patch probation: a CPU exception inside the live patch's new code, soon
; after it went live, rolls the patch back instead of halting. The shell
; then resumes right after the command that was running.

PATCH_PROBATION_MS equ 10000

; name: patch_fault
; in:   rdi = frame of a CPU exception
; out:  rax = frame to resume, the shell's resume point; CF=1 and rdi = the
;       frame if the fault is not one this can recover from
; clobbers: caller-saved
patch_fault:
    push rbx
    push r12
    push rbp
    mov rbp, rsp
    and rsp, -16                    ; any task, any stack depth
    mov rbx, rdi
    mov rax, [rbx + INT_FRAME_RIP]
    cmp rax, [rel patch_code]
    jb .fatal
    cmp rax, [rel patch_code_end]
    jae .fatal
    mov rax, [rel timer_ticks]
    sub rax, [rel patch_since]
    cmp rax, PATCH_PROBATION_MS
    jae .fatal
    cmp qword [rel shell_resume_rip], 0
    je .fatal
    test qword [rbx + INT_FRAME_RFLAGS], 0x200  ; IF=0: inside an IRQ handler,
    jz .fatal                                   ; whose EOI would be lost
    mov eax, [rel sched_current]
    cmp eax, [rel shell_resume_task]
    jne .fatal
    call patch_rollback
    mov r12, rax
    lea rdi, [rel guard_msg_head]
    call kputs
    mov rax, [rbx + INT_FRAME_VECTOR]
    lea rdi, [rel exc_names]
    lea rdi, [rdi + rax * 4]
    call kputs
    lea rdi, [rel guard_msg_at]
    call kputs
    mov rdi, [rbx + INT_FRAME_RIP]
    call kput_hex
    lea rdi, [rel guard_msg_rolled]
    call kputs
    mov rdi, r12
    call [rel jt_kput_dec]
    lea rdi, [rel patch_msg_functions]
    call kputs
    mov edi, 10
    call kputc
    mov rax, [rel shell_resume_rip]
    mov [rbx + INT_FRAME_RIP], rax
    mov rax, [rel shell_resume_rsp]
    mov [rbx + INT_FRAME_RSP], rax
    mov rax, rbx
    clc
    jmp .return
.fatal:
    mov rdi, rbx
    stc
.return:
    mov rsp, rbp
    pop rbp
    pop r12
    pop rbx
    ret

guard_msg_head   db 10, "[patch] #", 0
guard_msg_at     db " in new code at ", 0
guard_msg_rolled db ", rolled back ", 0

section .bss
alignb 8
shell_resume_rip  resq 1            ; 0 when no command runs
shell_resume_rsp  resq 1
shell_resume_task resd 1
section .text
