; Breakpoints: `int3` patched over the first byte of an instruction. They
; are one-shot: a hit puts the byte back, rewinds RIP onto it and pauses the
; task, which can then be stepped or resumed (kernel/debug.asm).

BP_VECTOR equ 3
BP_MAX    equ 8
BP_ADDR   equ 0
BP_BYTE   equ 8
BP_SIZE   equ 16                    ; BP_ADDR 0 marks a free slot

; name: bp_init
; in:   idt_init done
; out:  #BP handled by bp_trap
; clobbers: rax, rdi, rsi
bp_init:
    mov edi, BP_VECTOR
    lea rsi, [rel bp_trap]
    jmp isr_set_handler

; name: bp_find
; in:   rdi = address
; out:  rax = its breakpoint slot; CF=1 if none
; clobbers: rax, rcx
bp_find:
    lea rax, [rel bp_table]
    mov ecx, BP_MAX
.slot:
    cmp [rax + BP_ADDR], rdi
    je .found
    add rax, BP_SIZE
    dec ecx
    jnz .slot
    stc
    ret
.found:
    clc
    ret

; name: bp_set
; in:   rdi = address of an instruction in the kernel image
; out:  int3 written there; CF=1 if outside the image, already set or full
; clobbers: rax, rcx, rdx, rdi
bp_set:
    cmp rdi, KERNEL_PHYS
    jb .bad
    lea rax, [rel kernel_end_magic]
    cmp rdi, rax
    jae .bad
    call bp_find
    jnc .bad
    mov rdx, rdi
    xor edi, edi
    call bp_find
    jc .bad
    pushfq
    cli
    mov [rax + BP_ADDR], rdx
    mov cl, [rdx]
    mov [rax + BP_BYTE], cl
    mov byte [rdx], 0xcc
    popfq
    clc
    ret
.bad:
    stc
    ret

; name: bp_trap
; in:   rdi = frame after an int3
; out:  rax = frame to resume. On one of our breakpoints the byte is put
;       back and RIP rewound; a task (not the kernel task, not in an IRQ)
;       is paused and another one runs. Any other int3 is fatal.
; clobbers: caller-saved
bp_trap:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rbx + INT_FRAME_RIP]
    dec rdi
    call bp_find
    jc .foreign
    mov [rbx + INT_FRAME_RIP], rdi
    mov cl, [rax + BP_BYTE]
    mov [rdi], cl
    mov qword [rax + BP_ADDR], 0
    mov r12, rdi
    lea rdi, [rel bp_msg_hit]
    call kputs
    mov edi, [rel sched_current]
    call [rel jt_kput_dec]
    lea rdi, [rel bp_msg_at]
    call kputs
    mov rdi, r12
    call kput_hex
    mov eax, [rel sched_current]
    test eax, eax
    jz .continue
    test qword [rbx + INT_FRAME_RFLAGS], 0x200
    jz .continue
    imul eax, TASK_SIZE
    lea rcx, [rel sched_tasks]
    mov qword [rcx + rax + TASK_STATE], TASK_PAUSED
    lea rdi, [rel bp_msg_paused]
    call kputs
    mov rdi, rbx
    add rsp, 8
    pop r12
    pop rbx
    jmp sched_switch
.continue:
    lea rdi, [rel bp_msg_cleared]
    call kputs
    mov rax, rbx
    add rsp, 8
    pop r12
    pop rbx
    ret
.foreign:
    mov rdi, rbx
    add rsp, 8
    pop r12
    pop rbx
    jmp isr_default

; name: cmd_break
; in:   rdi = 0x and a hex address, or a kernel label
; out:  breakpoint set, or an error printed
; clobbers: caller-saved
cmd_break:
    push rbx
    call parse_addr
    jc .usage
    mov rbx, rax
    pushfq                          ; a task can hit the breakpoint at once:
    cli                             ; its report waits for this line
    mov rdi, rax
    call bp_set
    jc .refused_on
    lea rdi, [rel bp_msg_set]
    call kputs
    mov rdi, rbx
    call kput_hex
    mov edi, 10
    call kputc
    popfq
    pop rbx
    ret
.refused_on:
    popfq
    jmp .refused
.usage:
    lea rdi, [rel bp_msg_usage]
    call kputs
    pop rbx
    ret
.refused:
    lea rdi, [rel bp_msg_refused]
    call kputs
    pop rbx
    ret

bp_msg_hit     db "[break] task ", 0
bp_msg_at      db " hit ", 0
bp_msg_paused  db ", paused", 10, 0
bp_msg_cleared db ", cleared", 10, 0
bp_msg_set     db "[break] set at ", 0
bp_msg_usage   db "usage: break <0xaddress|label>", 10, 0
bp_msg_refused db "[break] not in kernel code, already set, or 8 set", 10, 0

section .bss
alignb 8
bp_table resb BP_SIZE * BP_MAX
section .text
