; Forge encoders for data movement and ALU instructions. Each takes its
; table parameter in rdi and reads the parsed operands from forge_ops.

; name: forge_enc_alu
; in:   rdi = base opcode (0x00 add, 0x08 or, 0x20 and, 0x28 sub, 0x30 xor,
;       0x38 cmp)
; out:  instruction built
; clobbers: caller-saved
forge_enc_alu:
    push rbx
    push r12
    push r13
    lea rbx, [rel forge_ops]
    mov r12, rdi
    call forge_size
    mov r13, rax
    xor r9d, r9d
    cmp r13, 1
    sete r9b                        ; r9 = 1 for byte operations
    mov rax, [rbx + FORGE_OP2 + OP_KIND]
    cmp rax, OPK_IMM
    je .immediate
    cmp rax, OPK_REG
    je .to_rm
    cmp qword [rbx + FORGE_OP1 + OP_KIND], OPK_REG
    jne forge_bad_operands
    lea rdi, [rbx + FORGE_OP2]      ; reg, mem: opcode + 3 (+ 2 for bytes)
    mov rsi, [rbx + FORGE_OP1 + OP_REG]
    lea rdx, [r12 + 3]
    sub rdx, r9
    jmp .rm
.to_rm:
    lea rdi, [rbx + FORGE_OP1]      ; r/m, reg: opcode + 1 (+ 0 for bytes)
    mov rsi, [rbx + FORGE_OP2 + OP_REG]
    lea rdx, [r12 + 1]
    sub rdx, r9
.rm:
    mov ecx, 1
    mov r8, r13
    call forge_rm
    jmp .done
.immediate:
    mov rdi, [rbx + FORGE_OP2 + OP_DISP]
    mov rsi, r13
    call forge_fits8
    je .imm8
    call forge_is_accumulator
    je .accumulator
    lea rdi, [rbx + FORGE_OP1]      ; 81 /n imm16/32
    mov rsi, r12
    shr rsi, 3
    mov edx, 0x81
    mov ecx, 1
    mov r8, r13
    xor r9d, r9d
    call forge_rm
    mov rdi, [rbx + FORGE_OP2 + OP_DISP]
    mov rsi, r13
    call forge_imm
    jmp .done
.imm8:
    cmp r13, 1
    jne .imm8_sext
    call forge_is_accumulator       ; al: short form even for a byte
    je .accumulator
.imm8_sext:
    lea rdi, [rbx + FORGE_OP1]      ; 83 /n ib, or 80 /n ib for bytes
    mov rsi, r12
    shr rsi, 3
    mov edx, 0x83
    cmp r13, 1
    jne .opcode8
    mov edx, 0x80
.opcode8:
    mov ecx, 1
    mov r8, r13
    xor r9d, r9d
    call forge_rm
    mov rdi, [rbx + FORGE_OP2 + OP_DISP]
    mov esi, 1
    call forge_ins_value
    jmp .done
.accumulator:
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call forge_rex
    lea edi, [r12 + 5]
    cmp r13, 1
    jne .acc_opcode
    lea edi, [r12 + 4]
.acc_opcode:
    call forge_ins_byte
    mov rdi, [rbx + FORGE_OP2 + OP_DISP]
    mov rsi, r13
    call forge_imm
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_is_accumulator
; in:   forge_ops
; out:  ZF=1 if the first operand is al, ax, eax or rax
; clobbers: rax
forge_is_accumulator:
    lea rax, [rel forge_ops]
    cmp qword [rax + FORGE_OP1 + OP_KIND], OPK_REG
    jne .done
    cmp qword [rax + FORGE_OP1 + OP_REG], 0
.done:
    ret

; name: forge_bad_operands
; in:   none
; out:  fails the assembly
; clobbers: everything
forge_bad_operands:
    lea rdi, [rel forge_msg_operands]
    jmp forge_fail

; name: forge_enc_mov
; in:   rdi = unused
; out:  instruction built
; clobbers: caller-saved
forge_enc_mov:
    push rbx
    push r12
    push r13
    lea rbx, [rel forge_ops]
    call forge_size
    mov r13, rax
    xor r9d, r9d
    cmp r13, 1
    sete r9b
    mov rax, [rbx + FORGE_OP2 + OP_KIND]
    cmp rax, OPK_IMM
    je .immediate
    cmp rax, OPK_REG
    je .to_rm
    cmp qword [rbx + FORGE_OP1 + OP_KIND], OPK_REG
    jne forge_bad_operands
    lea rdi, [rbx + FORGE_OP2]
    mov rsi, [rbx + FORGE_OP1 + OP_REG]
    mov edx, 0x8b
    sub rdx, r9
    jmp .rm
.to_rm:
    lea rdi, [rbx + FORGE_OP1]
    mov rsi, [rbx + FORGE_OP2 + OP_REG]
    mov edx, 0x89
    sub rdx, r9
.rm:
    mov ecx, 1
    mov r8, r13
    call forge_rm
    jmp .done
.immediate:
    mov r12, [rbx + FORGE_OP2 + OP_DISP]
    cmp qword [rbx + FORGE_OP1 + OP_KIND], OPK_REG
    je .to_reg
    lea rdi, [rbx + FORGE_OP1]      ; C7 /0 imm32 (C6 /0 ib for bytes)
    xor esi, esi
    mov edx, 0xc7
    sub rdx, r9
    mov ecx, 1
    mov r8, r13
    xor r9d, r9d
    call forge_rm
    mov rdi, r12
    mov rsi, r13
    call forge_imm
    jmp .done
.to_reg:
    cmp r13, 8
    jne .short_form
    mov rax, r12
    shr rax, 32
    jz .zero_extended               ; fits 32 unsigned bits: mov r32, imm32
    movsxd rax, r12d
    cmp rax, r12
    jne .short_form                 ; mov r64, imm64
    lea rdi, [rbx + FORGE_OP1]      ; sign-extended: C7 /0 imm32
    xor esi, esi
    mov edx, 0xc7
    mov ecx, 1
    mov r8d, 8
    xor r9d, r9d
    call forge_rm
    mov rdi, r12
    mov esi, 4
    call forge_ins_value
    jmp .done
.zero_extended:
    mov r13d, 4
.short_form:                        ; B8+r (B0+r for bytes), full immediate
    mov rdi, r13
    xor esi, esi
    lea rdx, [rbx + FORGE_OP1]
    xor ecx, ecx
    call forge_rex
    mov edi, [rbx + FORGE_OP1 + OP_REG]
    and edi, 7
    add edi, 0xb8
    cmp r13, 1
    jne .opcode
    sub edi, 8
.opcode:
    call forge_ins_byte
    mov rdi, r12
    mov rsi, r13
    call forge_ins_value
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_enc_lea
; in:   rdi = unused
; out:  instruction built
; clobbers: caller-saved
forge_enc_lea:
    sub rsp, 8
    lea rax, [rel forge_ops]
    cmp qword [rax + FORGE_OP1 + OP_KIND], OPK_REG
    jne forge_bad_operands
    cmp qword [rax + FORGE_OP2 + OP_KIND], OPK_MEM
    jne forge_bad_operands
    lea rdi, [rax + FORGE_OP2]
    mov rsi, [rax + FORGE_OP1 + OP_REG]
    mov edx, 0x8d
    mov ecx, 1
    mov r8, [rax + FORGE_OP1 + OP_SIZE]
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    ret

; name: forge_enc_test
; in:   rdi = unused
; out:  instruction built
; clobbers: caller-saved
forge_enc_test:
    push rbx
    push r12
    push r13
    lea rbx, [rel forge_ops]
    call forge_size
    mov r13, rax
    xor r9d, r9d
    cmp r13, 1
    sete r9b
    cmp qword [rbx + FORGE_OP2 + OP_KIND], OPK_IMM
    je .immediate
    cmp qword [rbx + FORGE_OP2 + OP_KIND], OPK_REG
    jne forge_bad_operands
    lea rdi, [rbx + FORGE_OP1]
    mov rsi, [rbx + FORGE_OP2 + OP_REG]
    mov edx, 0x85
    sub rdx, r9
    mov ecx, 1
    mov r8, r13
    call forge_rm
    jmp .done
.immediate:
    mov r12, r9
    call forge_is_accumulator
    jne .general
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call forge_rex
    mov edi, 0xa9
    sub rdi, r12
    call forge_ins_byte
    jmp .imm
.general:
    lea rdi, [rbx + FORGE_OP1]
    xor esi, esi
    mov edx, 0xf7
    sub rdx, r12
    mov ecx, 1
    mov r8, r13
    xor r9d, r9d
    call forge_rm
.imm:
    mov rdi, [rbx + FORGE_OP2 + OP_DISP]
    mov rsi, r13
    call forge_imm
.done:
    pop r13
    pop r12
    pop rbx
    ret
