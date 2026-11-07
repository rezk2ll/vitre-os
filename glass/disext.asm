; Disassembler: the two-byte opcode map (0x0f xx) as far as the kernel uses
; it: system instructions, conditional moves, jumps and sets, bit tests,
; and widening moves.

; name: dis_decode_0f
; in:   dis_pc after 0x0f, esi = operand size
; out:  the instruction appended; CF=1 if unknown
; clobbers: caller-saved
dis_decode_0f:
    push rbx
    push r12
    push r13
    mov r12d, esi
    mov rcx, [rel dis_pc]
    movzx ebx, byte [rcx]
    inc qword [rel dis_pc]
    lea rdi, [rel dis_0f_simple]
.simple:
    movzx eax, byte [rdi]
    inc rdi
    test eax, eax
    jz .not_simple
    cmp eax, ebx
    je .simple_found
    call dis_skip1
    jmp .simple
.simple_found:
    call dis_s
    jmp .ok
.not_simple:
    cmp ebx, 0x01
    je .table
    cmp ebx, 0x1f
    je .long_nop
    cmp ebx, 0x20
    je .mov_from_cr
    cmp ebx, 0x22
    je .mov_to_cr
    mov eax, ebx
    and eax, 0xf0
    cmp eax, 0x40
    je .cmov
    cmp eax, 0x80
    je .jcc32
    cmp eax, 0x90
    je .setcc
    cmp ebx, 0xa3
    je .bit
    cmp ebx, 0xab
    je .bit
    cmp ebx, 0xb3
    je .bit
    cmp ebx, 0xbb
    je .bit
    cmp ebx, 0xba
    je .bit_imm
    cmp ebx, 0xaf
    je .imul
    lea eax, [rbx - 0xb6]
    cmp eax, 2
    jb .widen
    lea eax, [rbx - 0xbe]
    cmp eax, 2
    jb .widen
    jmp .unknown
.table:                             ; lgdt, lidt, invlpg
    call dis_modrm
    and eax, 7
    lea rdi, [rel dis_n_lgdt]
    cmp eax, 2
    je .table_name
    lea rdi, [rel dis_n_lidt]
    cmp eax, 3
    je .table_name
    lea rdi, [rel dis_n_invlpg]
    cmp eax, 7
    jne .unknown
.table_name:
    call dis_mn
    jmp .rm_plain
.long_nop:
    call dis_modrm
    lea rdi, [rel dis_n_nop]
    call dis_mn
    mov esi, r12d
    mov edx, 1
    call dis_rm
    jmp .ok
.mov_from_cr:
    call dis_modrm
    mov r13d, eax
    lea rdi, [rel dis_n_mov]
    call dis_mn
    call .rm_reg64
    call dis_comma
    call .cr_name
    jmp .ok
.mov_to_cr:
    call dis_modrm
    mov r13d, eax
    lea rdi, [rel dis_n_mov]
    call dis_mn
    call .cr_name
    call dis_comma
    call .rm_reg64
    jmp .ok
.cmov:
    lea rdi, [rel dis_n_cmov]
    call dis_s
    call .cc_name
    mov edi, r12d
    mov esi, r12d
    call dis_form_reg_rm
    jmp .ok
.jcc32:
    mov dil, 'j'
    call dis_c
    call .cc_name
    mov esi, 4
    call dis_fetch
    add rax, [rel dis_pc]
    mov rdi, rax
    call dis_target
    jmp .ok
.setcc:
    call dis_modrm
    lea rdi, [rel dis_n_set]
    call dis_s
    call .cc_name
    mov esi, 1
    xor edx, edx
    call dis_rm
    jmp .ok
.bit:                               ; 0xa3 bt, 0xab bts, 0xb3 btr, 0xbb btc
    mov eax, ebx
    shr eax, 3
    and eax, 3
    call .bit_name
    mov esi, r12d
    call dis_form_rm_reg
    jmp .ok
.bit_imm:
    call dis_modrm
    and eax, 7
    cmp eax, 4
    jb .unknown
    sub eax, 4
    call .bit_name
    mov byte [rel dis_imm_len], 1
    mov esi, r12d
    mov edx, 1
    call dis_rm
    call dis_comma
    mov esi, 1
    mov edx, 1
    call dis_imm
    jmp .ok
.imul:
    lea rdi, [rel dis_n_imul]
    call dis_mn
    mov edi, r12d
    mov esi, r12d
    call dis_form_reg_rm
    jmp .ok
.widen:                             ; movzx/movsx r, r/m8 or r/m16
    lea rdi, [rel dis_n_movzx]
    cmp ebx, 0xbe
    jb .widen_name
    lea rdi, [rel dis_n_movsx]
.widen_name:
    call dis_mn
    call dis_modrm
    mov edi, eax
    mov esi, r12d
    call dis_reg
    call dis_comma
    mov esi, 1
    test ebx, 1
    jz .widen_rm
    mov esi, 2
.widen_rm:
    mov edx, 1
    call dis_rm
    jmp .ok
.rm_plain:
    mov esi, 8
    xor edx, edx
    call dis_rm
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
.cc_name:                           ; condition of opcode ebx, then a space
    mov eax, ebx
    and eax, 15
    lea rdi, [rel dis_cc_names]
    lea rdi, [rdi + rax * 4]
    jmp dis_mn
.bit_name:                          ; eax = 0 bt, 1 bts, 2 btr, 3 btc
    lea rdi, [rel dis_bit_names]
    lea rdi, [rdi + rax * 4]
    jmp dis_mn
.rm_reg64:                          ; the r/m field as a 64-bit register
    movzx edi, byte [rel dis_modrm_byte]
    and edi, 7
    test byte [rel dis_rex], REX_B
    jz .rm_reg64_name
    or edi, 8
.rm_reg64_name:
    mov esi, 8
    jmp dis_reg
.cr_name:                           ; "cr" and the reg field in r13d
    lea rdi, [rel dis_n_cr]
    call dis_s
    lea edi, [r13 + '0']
    jmp dis_c

; Two-byte opcodes without operands: opcode, name; 0 ends the table.
dis_0f_simple:
    db 0x05, "syscall", 0
    db 0x0b, "ud2", 0
    db 0x30, "wrmsr", 0
    db 0x31, "rdtsc", 0
    db 0x32, "rdmsr", 0
    db 0xa2, "cpuid", 0
    db 0

dis_bit_names db "bt",0,0,"bts",0,"btr",0,"btc",0
dis_n_lgdt    db "lgdt", 0
dis_n_lidt    db "lidt", 0
dis_n_invlpg  db "invlpg", 0
dis_n_nop     db "nop", 0
dis_n_cmov    db "cmov", 0
dis_n_set     db "set", 0
dis_n_movzx   db "movzx", 0
dis_n_movsx   db "movsx", 0
dis_n_cr      db "cr", 0
