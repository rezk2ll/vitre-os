; Forge encoders for one-operand groups, multiply, shifts and push/pop.

; name: forge_enc_unary
; in:   rdi = ModRM extension | base opcode << 8 (0xfe inc/dec, 0xf6 not,
;       neg, mul, imul, div, idiv)
; out:  instruction built
; clobbers: caller-saved
forge_enc_unary:
    push rbx
    mov rbx, rdi
    call forge_size
    mov r8, rax
    lea rdi, [rel forge_ops]
    mov esi, ebx
    and esi, 7
    mov edx, ebx
    shr edx, 8
    cmp r8, 1
    je .byte
    inc edx
.byte:
    mov ecx, 1
    xor r9d, r9d
    call forge_rm
    pop rbx
    ret

; name: forge_enc_imul
; in:   rdi = unused
; out:  instruction built: one, two or three operand form
; clobbers: caller-saved
forge_enc_imul:
    push rbx
    push r12
    push r13
    lea rbx, [rel forge_ops]
    mov rax, [rel forge_op_count]
    cmp rax, 1
    je .one
    call forge_size
    mov r13, rax
    lea r12, [rbx + FORGE_OP2]      ; source
    cmp qword [rel forge_op_count], 3
    je .three
    cmp qword [rbx + FORGE_OP2 + OP_KIND], OPK_IMM
    jne .two
    lea r12, [rbx + FORGE_OP1]      ; imul reg, imm is imul reg, reg, imm
    lea rax, [rbx + FORGE_OP2]
    jmp .with_imm
.two:
    mov rdi, r12
    mov rsi, [rbx + FORGE_OP1 + OP_REG]
    mov edx, 0xaf0f
    mov ecx, 2
    mov r8, r13
    xor r9d, r9d
    call forge_rm
    jmp .done
.three:
    lea rax, [rbx + FORGE_OP3]
.with_imm:
    mov rbx, [rax + OP_DISP]        ; rbx = immediate from here on
    mov rdi, rbx
    mov rsi, r13
    call forge_fits8
    mov edx, 0x6b
    je .encode
    mov edx, 0x69
.encode:
    push rdx
    sub rsp, 8
    mov rdi, r12
    lea rax, [rel forge_ops]
    mov rsi, [rax + FORGE_OP1 + OP_REG]
    mov ecx, 1
    mov r8, r13
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    pop rdx
    mov rdi, rbx
    mov esi, 1
    cmp edx, 0x6b
    je .imm
    mov rsi, r13
    call forge_imm
    jmp .done
.imm:
    call forge_ins_value
    jmp .done
.one:
    mov edi, 0xf605
    call forge_enc_unary
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_enc_shift
; in:   rdi = ModRM extension (4 shl, 5 shr, 7 sar)
; out:  instruction built: by 1, by an immediate or by cl
; clobbers: caller-saved
forge_enc_shift:
    push rbx
    push r12
    push r13
    lea rbx, [rel forge_ops]
    mov r12, rdi
    call forge_size
    mov r13, rax
    mov edx, 0xd3                   ; by cl
    cmp qword [rbx + FORGE_OP2 + OP_KIND], OPK_IMM
    jne .opcode
    mov edx, 0xd1
    cmp qword [rbx + FORGE_OP2 + OP_DISP], 1
    je .opcode
    mov edx, 0xc1
.opcode:
    cmp r13, 1
    jne .encode
    dec edx                         ; byte forms are one lower
.encode:
    push rdx
    sub rsp, 8
    lea rdi, [rbx + FORGE_OP1]
    mov rsi, r12
    mov ecx, 1
    mov r8, r13
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    pop rdx
    or edx, 1
    cmp edx, 0xc1
    jne .done
    mov rdi, [rbx + FORGE_OP2 + OP_DISP]
    mov esi, 1
    call forge_ins_value
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_enc_push
; in:   rdi = 0x50 push, 0x58 pop
; out:  instruction built
; clobbers: caller-saved
forge_enc_push:
    push rbx
    mov rbx, rdi
    lea rdx, [rel forge_ops]
    cmp qword [rdx + FORGE_OP1 + OP_KIND], OPK_REG
    jne forge_bad_operands
    mov edi, 4                      ; 64-bit by default, no REX.W
    xor esi, esi
    xor ecx, ecx
    call forge_rex
    lea rax, [rel forge_ops]
    mov edi, [rax + FORGE_OP1 + OP_REG]
    and edi, 7
    add edi, ebx
    call forge_ins_byte
    pop rbx
    ret
