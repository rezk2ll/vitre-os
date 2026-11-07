; Disassembler: the one-byte opcodes with operands beyond the ALU and
; push/pop forms: moves, immediates and branches. Opcode groups are in
; glass/disgrp.asm, the 0x0f map in glass/disext.asm.

; name: dis_imm_bytes
; in:   esi = operand size
; out:  eax = bytes of a full-size immediate: 2 for 16-bit operands, else 4
; clobbers: rax
dis_imm_bytes:
    mov eax, 4
    cmp esi, 2
    jne .done
    mov eax, 2
.done:
    ret

; name: dis_decode_more
; in:   edi = opcode byte, esi = operand size
; out:  the instruction appended; CF=1 if unknown
; clobbers: caller-saved
dis_decode_more:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    cmp ebx, 0x0f
    je .two_byte
    cmp ebx, 0x63
    je .movsxd
    cmp ebx, 0x68
    je .push_imm32
    cmp ebx, 0x6a
    je .push_imm8
    cmp ebx, 0x69
    je .imul_imm
    cmp ebx, 0x6b
    je .imul_imm
    lea eax, [rbx - 0x70]
    cmp eax, 16
    jb .jcc8
    lea eax, [rbx - 0x80]
    cmp eax, 4
    jb .group
    lea eax, [rbx - 0x84]
    cmp eax, 8
    jb .move
    cmp ebx, 0x8d
    je .lea
    cmp ebx, 0xa8
    je .test_acc
    cmp ebx, 0xa9
    je .test_acc
    lea eax, [rbx - 0xb0]
    cmp eax, 16
    jb .mov_imm
    cmp ebx, 0xc0
    je .group
    cmp ebx, 0xc1
    je .group
    lea eax, [rbx - 0xd0]
    cmp eax, 4
    jb .group
    cmp ebx, 0xc6
    je .mov_rm_imm
    cmp ebx, 0xc7
    je .mov_rm_imm
    cmp ebx, 0xcd
    je .int
    cmp ebx, 0xe4
    je .in_imm
    cmp ebx, 0xe6
    je .out_imm
    cmp ebx, 0xe8
    je .call32
    cmp ebx, 0xe9
    je .jmp32
    cmp ebx, 0xeb
    je .jmp8
    cmp ebx, 0xf6
    je .group
    cmp ebx, 0xf7
    je .group
    cmp ebx, 0xfe
    je .group
    cmp ebx, 0xff
    je .group
    jmp .unknown
.two_byte:
    jmp .unknown
.group:
    mov edi, ebx
    mov esi, r12d
    call dis_decode_group
    jmp .done
.movsxd:
    lea rdi, [rel dis_n_movsxd]
    call dis_mn
    mov edi, r12d
    mov esi, 4
    call dis_form_reg_rm
    jmp .ok
.push_imm32:
    mov r13d, 4
    jmp .push_imm
.push_imm8:
    mov r13d, 1
.push_imm:
    lea rdi, [rel dis_n_push]
    call dis_mn
    mov esi, r13d
    mov edx, 8
    call dis_imm
    jmp .ok
.imul_imm:
    lea rdi, [rel dis_n_imul]
    call dis_mn
    mov r13d, 1
    cmp ebx, 0x6b
    je .imul_len
    mov esi, r12d
    call dis_imm_bytes
    mov r13d, eax
.imul_len:
    mov [rel dis_imm_len], r13b
    mov edi, r12d
    mov esi, r12d
    call dis_form_reg_rm
    call dis_comma
    mov esi, r13d
    mov edx, r12d
    call dis_imm
    jmp .ok
.jcc8:
    mov dil, 'j'
    call dis_c
    mov eax, ebx
    and eax, 15
    lea rdi, [rel dis_cc_names]
    lea rdi, [rdi + rax * 4]
    call dis_mn
    mov esi, 1
    jmp .branch
.move:                              ; 0x84 to 0x8b: test, xchg, mov, mov
    shr eax, 1
    lea rdi, [rel dis_move_names]
    lea rdi, [rdi + rax * 8]
    call dis_mn
    mov esi, r12d
    test ebx, 1
    jnz .move_form
    mov esi, 1
.move_form:
    cmp ebx, 0x8a
    jae .move_reg_rm
    call dis_form_rm_reg
    jmp .ok
.move_reg_rm:
    mov edi, esi
    call dis_form_reg_rm
    jmp .ok
.lea:
    lea rdi, [rel dis_n_lea]
    call dis_mn
    mov edi, r12d
    mov esi, r12d
    call dis_form_reg_rm
    jmp .ok
.test_acc:
    lea rdi, [rel dis_move_names]
    call dis_mn
    mov r13d, 1
    cmp ebx, 0xa8
    je .test_acc_reg
    mov r13d, r12d
.test_acc_reg:
    xor edi, edi
    mov esi, r13d
    call dis_reg
    call dis_comma
    mov edx, r13d
    mov esi, r13d
    cmp esi, 4
    jbe .test_acc_imm
    mov esi, 4
.test_acc_imm:
    call dis_imm
    jmp .ok
.mov_imm:                           ; 0xb0 + r: imm8, 0xb8 + r: imm16/32/64
    lea rdi, [rel dis_n_mov]
    call dis_mn
    mov r13d, r12d
    cmp ebx, 0xb8
    jae .mov_imm_reg
    mov r13d, 1
.mov_imm_reg:
    mov edi, ebx
    and edi, 7
    test byte [rel dis_rex], REX_B
    jz .mov_imm_name
    or edi, 8
.mov_imm_name:
    mov esi, r13d
    call dis_reg
    call dis_comma
    mov esi, r13d
    cmp r13d, 8
    je .mov_imm64
    mov edx, r13d
    call dis_imm
    jmp .ok
.mov_imm64:
    call dis_fetch
    mov rdi, rax
    call dis_hex
    jmp .ok
.mov_rm_imm:
    call dis_modrm
    lea rdi, [rel dis_n_mov]
    call dis_mn
    mov esi, 1
    cmp ebx, 0xc6
    je .mov_rm_size
    mov esi, r12d
.mov_rm_size:
    mov r13d, esi
    cmp r13d, 4
    jbe .mov_rm_len
    mov r13d, 4
.mov_rm_len:
    mov [rel dis_imm_len], r13b
    push rsi
    sub rsp, 8
    mov edx, 1
    call dis_rm
    call dis_comma
    add rsp, 8
    pop rdx
    mov esi, r13d
    call dis_imm
    jmp .ok
.int:
    lea rdi, [rel dis_n_int]
    call dis_mn
    mov esi, 1
    mov edx, 1
    call dis_imm
    jmp .ok
.in_imm:
    lea rdi, [rel dis_n_in_al]
    call dis_s
    mov esi, 1
    mov edx, 1
    call dis_imm
    jmp .ok
.out_imm:
    lea rdi, [rel dis_n_out]
    call dis_mn
    mov esi, 1
    mov edx, 1
    call dis_imm
    lea rdi, [rel dis_n_comma_al]
    call dis_s
    jmp .ok
.call32:
    lea rdi, [rel dis_n_call]
    call dis_mn
    mov esi, 4
    jmp .branch
.jmp32:
    mov esi, 4
    jmp .jmp
.jmp8:
    mov esi, 1
.jmp:
    push rsi
    lea rdi, [rel dis_n_jmp]
    call dis_mn
    pop rsi
.branch:                            ; esi = displacement bytes
    call dis_fetch
    add rax, [rel dis_pc]
    mov rdi, rax
    call dis_target
    jmp .ok
.unknown:
    stc
    jmp .done
.ok:
    clc
.done:
    pop r13
    pop r12
    pop rbx
    ret

dis_cc_names     db "o",0,0,0,"no",0,0,"b",0,0,0,"ae",0,0,"e",0,0,0,"ne",0,0,"be",0,0,"a",0,0,0
                 db "s",0,0,0,"ns",0,0,"p",0,0,0,"np",0,0,"l",0,0,0,"ge",0,0,"le",0,0,"g",0,0,0
dis_move_names   db "test",0,0,0,0,"xchg",0,0,0,0,"mov",0,0,0,0,0,"mov",0,0,0,0,0
dis_n_movsxd     db "movsxd", 0
dis_n_imul       db "imul", 0
dis_n_lea        db "lea", 0
dis_n_mov        db "mov", 0
dis_n_int        db "int", 0
dis_n_in_al      db "in al, ", 0
dis_n_out        db "out", 0
dis_n_comma_al   db ", al", 0
dis_n_call       db "call", 0
dis_n_jmp        db "jmp", 0
