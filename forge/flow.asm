; Forge encoders for calls, jumps, conditions and extensions, and the
; mnemonic tables.

; name: forge_enc_call
; in:   rdi = 0 call, 1 jmp
; out:  instruction built: rel32 (or short jmp) to a label, or through r/m
; clobbers: caller-saved
forge_enc_call:
    sub rsp, 8
    lea rax, [rel forge_ops]
    cmp qword [rax + FORGE_OP1 + OP_KIND], OPK_IMM
    jne .indirect
    mov rsi, [rax + FORGE_OP1 + OP_DISP]
    test rdi, rdi
    jnz .jmp
    mov rdi, rsi
    mov esi, 0xe8
    call forge_near
    add rsp, 8
    ret
.jmp:
    mov rdi, rsi
    mov esi, 0xeb
    mov edx, 0xe9
    mov ecx, 1
    call forge_branch
    add rsp, 8
    ret
.indirect:
    lea rsi, [rdi * 2 + 2]          ; FF /2 call, FF /4 jmp
    lea rdi, [rax + FORGE_OP1]
    mov edx, 0xff
    mov ecx, 1
    mov r8d, 4
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    ret

; name: forge_enc_jcc
; in:   rdi = condition code
; out:  short or near conditional jump built
; clobbers: caller-saved
forge_enc_jcc:
    sub rsp, 8
    lea rax, [rel forge_ops]
    cmp qword [rax + FORGE_OP1 + OP_KIND], OPK_IMM
    jne forge_bad_operands
    lea esi, [rdi + 0x70]
    lea edx, [rdi + 0x80]
    shl edx, 8
    or edx, 0x0f
    mov ecx, 2
    mov rdi, [rax + FORGE_OP1 + OP_DISP]
    call forge_branch
    add rsp, 8
    ret

; name: forge_branch
; in:   rdi = target, rsi = short opcode, rdx = near opcode bytes, rcx = near
;       opcode length
; out:  short jump if this jump has always fitted, near jump otherwise
; clobbers: caller-saved
forge_branch:
    push rbx
    mov rbx, [rel forge_jump_index]
    cmp rbx, FORGE_JUMPS_MAX
    jae .many
    inc qword [rel forge_jump_index]
    lea rax, [rel forge_jump_long]
    cmp byte [rax + rbx], 0
    jne .near
    mov r8, rdi                     ; rel8 from the end of a 2-byte jump
    sub r8, [rel forge_origin]
    sub r8, [rel forge_pc]
    sub r8, 2
    movsx r9, r8b
    cmp r9, r8
    je .short
    cmp qword [rel forge_pass], 1   ; first pass: all jumps short
    je .short
    mov byte [rax + rbx], 1
    inc qword [rel forge_changed]
.near:
    mov rsi, rdx
    mov rdx, rcx
    call forge_near_bytes
    pop rbx
    ret
.short:
    push r8
    mov edi, esi
    call forge_ins_byte
    pop rdi
    call forge_ins_byte
    pop rbx
    ret
.many:
    lea rdi, [rel forge_msg_jumps]
    jmp forge_fail

; name: forge_near
; in:   rdi = target, rsi = one opcode byte
; out:  opcode and rel32 built
; clobbers: caller-saved
forge_near:
    mov edx, 1
; name: forge_near_bytes
; in:   rdi = target, rsi = opcode bytes, rdx = opcode length
; out:  opcode and rel32 built
; clobbers: caller-saved
forge_near_bytes:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
.opcode:
    mov edi, r12d
    call forge_ins_byte
    shr r12, 8
    dec r13
    jnz .opcode
    mov rdi, rbx
    sub rdi, [rel forge_origin]
    sub rdi, [rel forge_pc]
    sub rdi, [rel forge_ins_len]
    sub rdi, 4
    mov esi, 4
    call forge_ins_value
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_enc_setcc
; in:   rdi = condition code
; out:  setcc r/m8 built
; clobbers: caller-saved
forge_enc_setcc:
    sub rsp, 8
    lea edx, [rdi + 0x90]
    shl edx, 8
    or edx, 0x0f
    lea rdi, [rel forge_ops]
    xor esi, esi
    mov ecx, 2
    mov r8d, 1
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    ret

; name: forge_enc_cmovcc
; in:   rdi = condition code
; out:  cmovcc reg, r/m built
; clobbers: caller-saved
forge_enc_cmovcc:
    lea edx, [rdi + 0x40]
    shl edx, 8
    or edx, 0x0f
; name: forge_enc_reg_rm
; in:   rdx = opcode bytes (two)
; out:  "op reg, r/m" built with the first operand's size
; clobbers: caller-saved
forge_enc_reg_rm:
    sub rsp, 8
    lea rax, [rel forge_ops]
    cmp qword [rax + FORGE_OP1 + OP_KIND], OPK_REG
    jne forge_bad_operands
    lea rdi, [rax + FORGE_OP2]
    mov rsi, [rax + FORGE_OP1 + OP_REG]
    mov ecx, 2
    mov r8, [rax + FORGE_OP1 + OP_SIZE]
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    ret

; name: forge_enc_movx
; in:   rdi = 0xb6 movzx, 0xbe movsx
; out:  movzx/movsx reg, r/m8 or r/m16 built
; clobbers: caller-saved
forge_enc_movx:
    lea rax, [rel forge_ops]
    mov rcx, [rax + FORGE_OP2 + OP_SIZE]
    cmp rcx, 1
    je .byte
    cmp rcx, 2
    jne forge_bad_operands
    inc edi
.byte:
    mov edx, edi
    shl edx, 8
    or edx, 0x0f
    jmp forge_enc_reg_rm

; name: forge_enc_movsxd
; in:   rdi = unused
; out:  movsxd r64, r/m32 built
; clobbers: caller-saved
forge_enc_movsxd:
    sub rsp, 8
    lea rax, [rel forge_ops]
    cmp qword [rax + FORGE_OP1 + OP_KIND], OPK_REG
    jne forge_bad_operands
    lea rdi, [rax + FORGE_OP2]
    mov rsi, [rax + FORGE_OP1 + OP_REG]
    mov edx, 0x63
    mov ecx, 1
    mov r8d, 8
    xor r9d, r9d
    call forge_rm
    add rsp, 8
    ret

forge_msg_jumps db "too many jumps", 0
