; Programs: `run <file> [arguments]` assembles a user file with Forge into
; fresh pages and calls its first line with rdi = the arguments. The program
; returns with ret, and it may call any kernel function by name.

RUN_PAGES equ 16

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
    mov rbx, rdi
    mov r12, rdi
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
    mov r8d, RUN_PAGES * PAGE_SIZE
    call forge_assemble
    jc .error
    add rax, r15
    mov [rel run_code], r15
    mov [rel run_code_end], rax
    mov rdi, r12
    call r15
    mov qword [rel run_code], 0
    mov qword [rel run_code_end], 0
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
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: run_fault
; in:   rdi = frame of a CPU exception
; out:  rax = frame to resume, the shell's resume point, when the shell was
;       running a program: its pages freed and the fault on the log. CF=1
;       and rdi = the frame otherwise
; clobbers: caller-saved
run_fault:
    push rbx
    push rbp
    mov rbp, rsp
    and rsp, -16                    ; any stack depth
    mov rbx, rdi
    cmp qword [rel run_code], 0
    je .fatal
    cmp qword [rel shell_resume_rip], 0
    je .fatal
    test qword [rbx + INT_FRAME_RFLAGS], 0x200  ; IF=0: inside an IRQ handler,
    jz .fatal                                   ; whose EOI would be lost
    mov eax, [rel sched_current]
    cmp eax, [rel shell_resume_task]
    jne .fatal
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

section .bss
alignb 8
run_code     resq 1                 ; the running program, 0 when none
run_code_end resq 1
section .text
