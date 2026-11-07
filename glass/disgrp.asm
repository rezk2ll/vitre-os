; Disassembler: opcode groups, where the ModRM reg field picks the
; operation: group 1 (0x80-0x83), shifts (0xc0, 0xc1, 0xd0-0xd3), group 3
; (0xf6, 0xf7) and groups 4 and 5 (0xfe, 0xff).

; name: dis_decode_group
; in:   edi = opcode byte, esi = operand size
; out:  the instruction appended; CF=1 if the reg field names no operation
; clobbers: caller-saved
dis_decode_group:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    call dis_modrm
    and eax, 7
    mov r13d, eax                   ; operation
    cmp ebx, 0x84
    jb .group1
    cmp ebx, 0xf6
    jb .shift
    cmp ebx, 0xfe
    jb .group3
    jmp .group45
.group1:
    mov edi, r13d
    call dis_alu_name
    mov r13d, 1                     ; 0x80, 0x82, 0x83: imm8
    cmp ebx, 0x81
    jne .group1_size
    mov esi, r12d
    call dis_imm_bytes
    mov r13d, eax
.group1_size:
    mov [rel dis_imm_len], r13b
    mov esi, r12d
    test ebx, 1
    jnz .rm_imm
    mov esi, 1
.rm_imm:                            ; esi = size, r13d = immediate bytes
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
.shift:
    lea rdi, [rel dis_shift_names]
    lea rdi, [rdi + r13 * 4]
    call dis_mn
    xor r13d, r13d
    cmp ebx, 0xc1
    ja .shift_size
    mov r13d, 1
.shift_size:
    mov [rel dis_imm_len], r13b
    mov esi, r12d
    test ebx, 1
    jnz .shift_rm
    mov esi, 1
.shift_rm:
    test r13d, r13d
    jnz .rm_imm
    mov edx, 1
    call dis_rm
    call dis_comma
    lea rdi, [rel dis_one_text]
    cmp ebx, 0xd2
    jb .shift_text
    lea rdi, [rel dis_reg8 + 4]     ; "cl"
.shift_text:
    call dis_s
    jmp .ok
.group3:
    cmp r13d, 1
    je .unknown
    lea rdi, [rel dis_group3_names]
    lea rdi, [rdi + r13 * 8]
    call dis_mn
    mov esi, r12d
    cmp ebx, 0xf7
    je .group3_size
    mov esi, 1
.group3_size:
    test r13d, r13d
    jnz .rm_only
    mov r13d, esi                   ; test: an immediate follows
    cmp r13d, 4
    jbe .group3_len
    mov r13d, 4
.group3_len:
    mov [rel dis_imm_len], r13b
    jmp .rm_imm
.group45:                           ; 0xfe: inc/dec r/m8; 0xff: inc, dec, call, jmp, push
    cmp ebx, 0xfe
    jne .group5
    cmp r13d, 2
    jae .unknown
    mov r12d, 1
.group5:
    cmp r13d, 7
    je .unknown
    cmp r13d, 3                     ; 3 and 5 are far forms
    je .unknown
    cmp r13d, 5
    je .unknown
    lea rdi, [rel dis_group5_names]
    lea rdi, [rdi + r13 * 8]
    call dis_mn
    mov esi, r12d
    cmp r13d, 2
    jb .rm_only
    mov esi, 8
.rm_only:
    mov edx, 1
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

dis_shift_names  db "rol",0,"ror",0,"rcl",0,"rcr",0,"shl",0,"shr",0,"sal",0,"sar",0
dis_group3_names db "test",0,0,0,0,"?",0,0,0,0,0,0,0,"not",0,0,0,0,0,"neg",0,0,0,0,0
                 db "mul",0,0,0,0,0,"imul",0,0,0,0,"div",0,0,0,0,0,"idiv",0,0,0,0
dis_group5_names db "inc",0,0,0,0,0,"dec",0,0,0,0,0,"call",0,0,0,0,"?",0,0,0,0,0,0,0
                 db "jmp",0,0,0,0,0,"?",0,0,0,0,0,0,0,"push",0,0,0,0
dis_one_text     db "1", 0
