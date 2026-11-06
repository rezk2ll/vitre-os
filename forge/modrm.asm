; Forge ModRM encoding: prefixes, opcode, ModRM, SIB and displacement for
; a register or memory operand.

; name: forge_rex
; in:   rdi = operand size, rsi = reg field (0-15), rdx = rm operand,
;       rcx = 1 if the reg field is an 8-bit register
; out:  0x66 and a REX prefix appended when the operands need them
; clobbers: rax, rdi, r8
forge_rex:
    cmp rdi, 2
    jne .no_66
    push rdi
    mov edi, 0x66
    call forge_ins_byte
    pop rdi
.no_66:
    xor r8d, r8d
    cmp rdi, 8
    jne .no_w
    or r8d, 0x48
.no_w:
    test rcx, rcx                   ; spl, bpl, sil, dil need a REX
    jz .reg_ext
    lea rax, [rsi - 4]
    cmp rax, 4
    jae .reg_ext
    or r8d, 0x40
.reg_ext:
    cmp rsi, 8
    jb .rm
    or r8d, 0x44
.rm:
    test rdx, rdx
    jz .emit
    cmp qword [rdx + OP_KIND], OPK_REG
    jne .memory
    mov rax, [rdx + OP_REG]
    cmp rax, 8
    jb .rm_low
    or r8d, 0x41
    jmp .emit
.rm_low:
    cmp qword [rdx + OP_SIZE], 1
    jne .emit
    cmp rax, 4
    jb .emit
    or r8d, 0x40
    jmp .emit
.memory:
    mov rax, [rdx + OP_BASE]
    cmp rax, 8
    jl .index
    or r8d, 0x41
.index:
    mov rax, [rdx + OP_INDEX]
    cmp rax, 8
    jl .emit
    or r8d, 0x42
.emit:
    test r8d, r8d
    jz .done
    mov edi, r8d
    call forge_ins_byte
.done:
    ret

; name: forge_rm
; in:   rdi = rm operand, rsi = reg field (0-15), rdx = opcode bytes (low byte
;       first), rcx = opcode length, r8 = operand size, r9 = 1 if the reg
;       field is an 8-bit register
; out:  prefixes, opcode, ModRM, SIB and displacement appended
; clobbers: caller-saved
forge_rm:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, r8
    mov rdx, rbx
    mov rcx, r9
    call forge_rex
.opcode:
    mov edi, r13d
    call forge_ins_byte
    shr r13, 8
    dec r14
    jnz .opcode
    mov r15, r12
    and r15d, 7
    shl r15d, 3                     ; reg field in place
    cmp qword [rbx + OP_KIND], OPK_REG
    jne .memory
    mov edi, [rbx + OP_REG]
    and edi, 7
    or edi, r15d
    or edi, 0xc0
    call forge_ins_byte
    jmp .done
.memory:
    cmp qword [rbx + OP_RIP], 0
    je .not_rip
    lea edi, [r15 + 5]
    call forge_ins_byte
    mov rax, [rel forge_ins_len]
    mov [rel forge_rip_pos], rax
    mov rax, [rbx + OP_DISP]
    mov [rel forge_rip_target], rax
    xor edi, edi
    mov esi, 4
    call forge_ins_value
    jmp .done
.not_rip:
    mov r12, [rbx + OP_BASE]
    mov r13, [rbx + OP_INDEX]
    cmp r12, -1
    jne .based
    lea edi, [r15 + 4]              ; no base: SIB with base 101, disp32
    call forge_ins_byte
    mov eax, 5
    cmp r13, -1
    jne .absolute_index
    or eax, 4 << 3
    jmp .absolute_sib
.absolute_index:
    mov ecx, r13d
    and ecx, 7
    shl ecx, 3
    or eax, ecx
    mov ecx, [rbx + OP_SCALE]
    shl ecx, 6
    or eax, ecx
.absolute_sib:
    mov edi, eax
    call forge_ins_byte
    mov rdi, [rbx + OP_DISP]
    mov esi, 4
    call forge_ins_value
    jmp .done
.based:
    mov r14, [rbx + OP_DISP]        ; mod: 0 none, 1 disp8, 2 disp32
    xor eax, eax
    test r14, r14
    jnz .sized
    mov ecx, r12d
    and ecx, 7
    cmp ecx, 5                      ; rbp and r13 have no mod 0 form
    jne .mod
.sized:
    movsx rcx, r14b
    mov eax, 1
    cmp rcx, r14
    je .mod
    mov eax, 2
.mod:
    mov r14d, eax
    shl eax, 6
    or eax, r15d
    mov ecx, r12d
    and ecx, 7
    cmp r13, -1
    jne .sib
    cmp ecx, 4                      ; rsp and r12 always take a SIB
    je .sib
    or eax, ecx
    mov edi, eax
    call forge_ins_byte
    jmp .disp
.sib:
    or eax, 4
    mov edi, eax
    call forge_ins_byte
    mov eax, r12d
    and eax, 7
    mov ecx, 4 << 3                 ; no index
    cmp r13, -1
    je .sib_index
    mov ecx, r13d
    and ecx, 7
    shl ecx, 3
.sib_index:
    or eax, ecx
    mov ecx, [rbx + OP_SCALE]
    shl ecx, 6
    or eax, ecx
    mov edi, eax
    call forge_ins_byte
.disp:
    test r14d, r14d
    jz .done
    mov rdi, [rbx + OP_DISP]
    mov esi, 1
    cmp r14d, 1
    je .disp_bytes
    mov esi, 4
.disp_bytes:
    call forge_ins_value
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
