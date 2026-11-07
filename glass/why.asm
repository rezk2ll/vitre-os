; `why x y`: the task and the call chain that last drew a pixel, from the
; provenance map (glass/provenance.asm).

; name: cmd_why
; in:   rdi = "x y"
; out:  the task and the call chain that drew that pixel, one frame a line
; clobbers: caller-saved
cmd_why:
    push rbx
    push r12
    push r13
    call prov_point
    jc .usage
    cmp qword [rel prov_map], 0
    je .off
    imul rdx, [rel fb_width]
    add rax, rdx
    mov rcx, [rel prov_map]
    mov eax, [rcx + rax * 4]
    test eax, eax
    jz .unknown
    dec eax
    shl rax, 6
    add rax, [rel prov_chains]
    mov rbx, rax
    lea rdi, [rel prov_msg_task]
    call kputs
    mov edi, [rbx + PROV_TASK]
    call [rel jt_kput_dec]
    mov edi, ' '
    call kputc
    mov eax, [rbx + PROV_TASK]
    imul eax, TASK_SIZE
    lea rdi, [rel sched_tasks + TASK_NAME]
    add rdi, rax
    call kputs
    mov edi, 10
    call kputc
    xor r12d, r12d
.frame:
    cmp r12d, [rbx + PROV_COUNT]
    jae .done
    mov r13, [rbx + PROV_FRAMES + r12 * 8]
    lea rdi, [rel prov_msg_frame]
    call kputs
    mov rdi, r13
    call kput_hex
    mov rdi, r13
    call prov_function
    jc .eol
    sub r13, rax
    push rdx
    mov edi, ' '
    call kputc
    pop rdi
    add rdi, SYM_NAME
    call prov_name
    mov edi, '+'
    call kputc
    mov rdi, r13
    call [rel jt_kput_dec]
.eol:
    mov edi, 10
    call kputc
    inc r12d
    jmp .frame
.usage:
    lea rdi, [rel prov_msg_usage]
    jmp .print
.off:
    lea rdi, [rel prov_msg_off]
    jmp .print
.unknown:
    lea rdi, [rel prov_msg_unknown]
.print:
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: prov_name
; in:   rdi = a symbol record's name field
; out:  the name, at most 32 characters, on the console
; clobbers: caller-saved
prov_name:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    xor r12d, r12d
.char:
    movzx edi, byte [rbx + r12]
    test edi, edi
    jz .ret
    call kputc
    inc r12d
    cmp r12d, 32
    jb .char
.ret:
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: prov_point
; in:   rdi = "x y"
; out:  rax = x, rdx = y; CF=1 unless both are decimal and on the screen
; clobbers: rax, rcx, rdx, rdi
prov_point:
    xor eax, eax
    call .number
    jc .ret
    cmp byte [rdi], ' '
    jne .bad
    inc rdi
    mov rdx, rax
    call .number
    jc .ret
    cmp byte [rdi], 0
    jne .bad
    xchg rax, rdx
    cmp rax, [rel fb_width]
    jae .bad
    cmp rdx, [rel fb_height]
    jae .bad
    clc
.ret:
    ret
.bad:
    stc
    ret
.number:                            ; rdi = digits; rax = value, CF=1 if none
    push rdx
    xor eax, eax
    xor edx, edx
.digit:
    movzx ecx, byte [rdi]
    sub ecx, '0'
    cmp ecx, 9
    ja .end
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    inc edx
    jmp .digit
.end:
    cmp edx, 1
    pop rdx
    ret

prov_msg_task    db "[why] task ", 0
prov_msg_frame   db "[why]   ", 0
prov_msg_usage   db "usage: why <x> <y>", 10, 0
prov_msg_off     db "[why] no provenance map", 10, 0
prov_msg_unknown db "[why] nothing recorded there", 10, 0
