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

run_msg_prefix db "[run] ", 0

section .bss
alignb 8
run_code     resq 1                 ; the running program, 0 when none
run_code_end resq 1
section .text
