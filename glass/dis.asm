; x86-64 disassembler for the instructions the kernel uses. Output is Intel
; syntax in NASM's spelling; unknown bytes come out as "db 0x..", one byte
; at a time, so decoding never runs ahead of what it understands.

DIS_LINE_MAX equ 96

; name: dis_one
; in:   rdi = instruction address, rsi = output buffer of DIS_LINE_MAX bytes
; out:  rax = instruction length; the buffer holds its text, zero-terminated
; clobbers: caller-saved
dis_one:
    push rbx
    push r12
    push r13
    mov [rel dis_pc], rdi
    mov [rel dis_start], rdi
    mov [rel dis_out], rsi
    mov r13, rsi
    xor eax, eax
    mov [rel dis_rex], al
    mov [rel dis_opsize], al
    mov [rel dis_rep], al
    mov [rel dis_imm_len], al
.prefix:
    mov rcx, [rel dis_pc]
    mov rax, rcx
    sub rax, [rel dis_start]
    cmp rax, 4                      ; more prefixes than that: not code we wrote
    jae .opcode
    movzx ebx, byte [rcx]
    cmp ebx, 0x66
    je .opsize
    cmp ebx, 0xf3
    je .rep
    cmp ebx, 0xf2
    je .rep
    cmp ebx, 0xf0
    je .lock
    lea eax, [rbx - 0x40]
    cmp eax, 16
    jae .opcode
    mov [rel dis_rex], bl
    inc qword [rel dis_pc]
    jmp .opcode
.opsize:
    mov byte [rel dis_opsize], 1
    inc qword [rel dis_pc]
    jmp .prefix
.rep:
    mov [rel dis_rep], bl
    inc qword [rel dis_pc]
    jmp .prefix
.lock:
    lea rdi, [rel dis_lock_name]
    call dis_s
    inc qword [rel dis_pc]
    jmp .prefix
.opcode:
    mov rcx, [rel dis_pc]
    movzx ebx, byte [rcx]
    inc qword [rel dis_pc]
    mov r12d, 4                     ; operand size
    cmp byte [rel dis_opsize], 0
    je .rex_w
    mov r12d, 2
.rex_w:
    test byte [rel dis_rex], REX_W
    jz .sized
    mov r12d, 8
.sized:
    mov edi, ebx
    mov esi, r12d
    call dis_decode
    jnc .end
    mov rax, [rel dis_start]        ; not understood: one byte of data
    lea rcx, [rax + 1]
    mov [rel dis_pc], rcx
    mov [rel dis_out], r13
    lea rdi, [rel dis_db]
    call dis_s
    mov rax, [rel dis_start]
    movzx edi, byte [rax]
    call dis_hex
.end:
    mov rax, [rel dis_out]
    cmp byte [rax - 1], ' '
    jne .terminate
    dec rax
.terminate:
    mov byte [rax], 0
    mov rax, [rel dis_pc]
    sub rax, [rel dis_start]
    pop r13
    pop r12
    pop rbx
    ret

; name: dis_decode
; in:   edi = opcode byte, esi = operand size; prefixes in the dis_* state
; out:  the instruction appended; CF=1 if it is not one this decoder knows
;       (the output is then rewound by the caller)
; clobbers: caller-saved
dis_decode:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    lea rdi, [rel dis_simple]       ; no operands
.simple:
    movzx eax, byte [rdi]
    inc rdi
    cmp al, 0xff
    je .not_simple
    cmp eax, ebx
    je .simple_found
    call dis_skip2
    jmp .simple
.simple_found:
    mov rax, rdi
    call dis_skip1
    cmp byte [rdi], 0
    je .simple_one_size
    cmp r12d, 2                     ; 16-bit spellings (movsw, cbw) are not listed
    je .unknown
    cmp r12d, 8                     ; the REX.W spelling comes second
    je .simple_print
.simple_one_size:
    mov rdi, rax
.simple_print:
    lea rax, [rel dis_rep_name]
    cmp byte [rel dis_rep], 0xf3
    je .simple_rep
    lea rax, [rel dis_repne_name]
    cmp byte [rel dis_rep], 0xf2
    jne .simple_out
.simple_rep:
    push rdi
    mov rdi, rax
    call dis_s
    pop rdi
.simple_out:
    call dis_s
    jmp .ok
.not_simple:
    cmp ebx, 0x0f
    je .other
    cmp ebx, 0x40                   ; add/or/adc/sbb/and/sub/xor/cmp forms
    jae .push_pop
    mov eax, ebx
    and eax, 7
    cmp eax, 6
    jae .unknown
    mov edi, ebx
    shr edi, 3
    call dis_alu_name
    mov eax, ebx
    and eax, 7
    mov esi, r12d
    test eax, 1
    jnz .alu_wide
    mov esi, 1
.alu_wide:
    cmp eax, 2
    jb .rm_reg
    cmp eax, 4
    jb .reg_rm
    mov r13d, esi                   ; al/eax/rax, imm of at most 4 bytes
    xor edi, edi
    call dis_reg
    call dis_comma
    mov edx, r13d
    mov esi, r13d
    cmp esi, 4
    jbe .acc_imm
    mov esi, 4
.acc_imm:
    call dis_imm
    jmp .ok
.push_pop:
    lea eax, [rbx - 0x50]
    cmp eax, 16
    jae .other
    lea rdi, [rel dis_n_push]
    cmp eax, 8
    jb .push_pop_name
    lea rdi, [rel dis_n_pop]
.push_pop_name:
    call dis_mn
    mov edi, ebx
    and edi, 7
    test byte [rel dis_rex], REX_B
    jz .push_pop_reg
    or edi, 8
.push_pop_reg:
    mov esi, 8
    call dis_reg
    jmp .ok
.other:
    jmp .unknown
.rm_reg:
    call dis_form_rm_reg
    jmp .ok
.reg_rm:
    mov edi, esi
    call dis_form_reg_rm
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

; name: dis_skip1
; in:   rdi = string
; out:  rdi past its terminating zero
; clobbers: rdi
dis_skip1:
    cmp byte [rdi], 0
    je .past
    inc rdi
    jmp dis_skip1
.past:
    inc rdi
    ret

; name: dis_skip2
; in:   rdi = two strings
; out:  rdi past both
; clobbers: rdi
dis_skip2:
    call dis_skip1
    jmp dis_skip1

; name: dis_mn
; in:   rdi = mnemonic
; out:  the mnemonic and a space appended
; clobbers: rax, rcx, rdi
dis_mn:
    call dis_s
    mov dil, ' '
    jmp dis_c

; name: dis_alu_name
; in:   edi = 0-7, the ALU operation of an opcode or of a group 1 reg field
; out:  its mnemonic and a space appended
; clobbers: rax, rcx, rdi
dis_alu_name:
    lea rax, [rel dis_alu_names]
    lea rdi, [rax + rdi * 4]
    jmp dis_mn

; name: dis_imm
; in:   esi = immediate bytes (1, 2 or 4), edx = operand size
; out:  the immediate read and appended, sign-extended to the operand size
; clobbers: caller-saved
dis_imm:
    push rdx
    call dis_fetch
    pop rcx
    mov rdi, rax
    cmp ecx, 8
    je .signed
    shl ecx, 3
    mov eax, 1
    shl rax, cl
    dec rax
    and rdi, rax
    jmp dis_hex
.signed:
    xor esi, esi
    jmp dis_signed

; name: dis_form_rm_reg
; in:   esi = operand size, dis_pc at a ModRM byte
; out:  "rm, reg" appended
; clobbers: caller-saved
dis_form_rm_reg:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    call dis_modrm
    mov ebx, eax
    mov esi, r12d
    xor edx, edx
    call dis_rm
    call dis_comma
    mov edi, ebx
    mov esi, r12d
    call dis_reg
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: dis_form_reg_rm
; in:   edi = register size, esi = r/m size, dis_pc at a ModRM byte
; out:  "reg, rm" appended
; clobbers: caller-saved
dis_form_reg_rm:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    mov ebx, edi
    call dis_modrm
    mov edi, eax
    mov esi, ebx
    call dis_reg
    call dis_comma
    mov esi, r12d
    xor edx, edx
    call dis_rm
    add rsp, 8
    pop r12
    pop rbx
    ret

; Opcodes without operands: opcode, name, name with REX.W (empty: the same).
dis_simple:
    db 0x90, "nop", 0, 0
    db 0x98, "cwde", 0, "cdqe", 0
    db 0x99, "cdq", 0, "cqo", 0
    db 0x9c, "pushfq", 0, 0
    db 0x9d, "popfq", 0, 0
    db 0xa4, "movsb", 0, 0
    db 0xa5, "movsd", 0, "movsq", 0
    db 0xaa, "stosb", 0, 0
    db 0xab, "stosd", 0, "stosq", 0
    db 0xac, "lodsb", 0, 0
    db 0xad, "lodsd", 0, "lodsq", 0
    db 0xc3, "ret", 0, 0
    db 0xc9, "leave", 0, 0
    db 0xcc, "int3", 0, 0
    db 0xcf, "iretd", 0, "iretq", 0
    db 0xec, "in al, dx", 0, 0
    db 0xed, "in eax, dx", 0, 0
    db 0xee, "out dx, al", 0, 0
    db 0xef, "out dx, eax", 0, 0
    db 0xf4, "hlt", 0, 0
    db 0xf5, "cmc", 0, 0
    db 0xf8, "clc", 0, 0
    db 0xf9, "stc", 0, 0
    db 0xfa, "cli", 0, 0
    db 0xfb, "sti", 0, 0
    db 0xfc, "cld", 0, 0
    db 0xfd, "std", 0, 0
    db 0xff

dis_alu_names db "add",0,"or",0,0,"adc",0,"sbb",0,"and",0,"sub",0,"xor",0,"cmp",0
dis_n_push    db "push", 0
dis_n_pop     db "pop", 0
dis_rep_name  db "rep ", 0
dis_repne_name db "repne ", 0
dis_lock_name db "lock ", 0
dis_db        db "db ", 0
