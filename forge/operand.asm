; Forge operands: registers, memory references and immediates.

OP_KIND  equ 0                      ; OPK_*
OP_SIZE  equ 8                      ; 1, 2, 4, 8, or 0 for memory without a size
OP_REG   equ 16                     ; register number
OP_BASE  equ 24                     ; memory base register, -1 for none
OP_INDEX equ 32                     ; memory index register, -1 for none
OP_SCALE equ 40
OP_DISP  equ 48                     ; displacement, RIP target or immediate
OP_RIP   equ 56                     ; 1 for [rel ...]
OP_SIZEOF equ 64

OPK_REG  equ 1
OPK_MEM  equ 2
OPK_IMM  equ 3

FORGE_OPS_MAX equ 3

; name: forge_operands
; in:   forge_cur after the mnemonic
; out:  forge_ops filled, forge_op_count = number of operands
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_operands:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [rel forge_ops]
    xor r12d, r12d
.clear:
    mov qword [rbx + r12 * 8], 0
    inc r12d
    cmp r12d, FORGE_OPS_MAX * OP_SIZEOF / 8
    jb .clear
    xor r12d, r12d
    call forge_skip
    call forge_at_end
    je .done
.operand:
    cmp r12d, FORGE_OPS_MAX
    jae .bad
    mov rdi, rbx
    call forge_operand
    inc r12d
    add rbx, OP_SIZEOF
    call forge_skip
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .done
    cmp byte [rax], ','
    jne .done
    inc qword [rel forge_cur]
    jmp .operand
.done:
    mov [rel forge_op_count], r12
    add rsp, 8
    pop r12
    pop rbx
    ret
.bad:
    lea rdi, [rel forge_msg_operands]
    jmp forge_fail

; name: forge_operand
; in:   rdi = operand to fill, forge_cur at it
; out:  operand parsed
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_operand:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call forge_skip
    mov r12, [rel forge_cur]
    lea rdi, [rel forge_sym_word]
    call forge_ident
    test rax, rax
    jz .not_name
    lea rdi, [rel forge_sym_word]
    call forge_size_keyword
    jnc .sized
    lea rdi, [rel forge_sym_word]
    call forge_register
    jc .not_name
    mov qword [rbx + OP_KIND], OPK_REG
    mov [rbx + OP_REG], rax
    mov [rbx + OP_SIZE], rdx
    jmp .done
.sized:
    mov [rbx + OP_SIZE], rax
    call forge_skip
    mov r12, [rel forge_cur]
.not_name:
    mov [rel forge_cur], r12
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .immediate
    cmp byte [rax], '['
    je .memory
.immediate:
    cmp qword [rbx + OP_SIZE], 0    ; "byte 5" is not in the dialect
    jne .bad
    call forge_expr
    mov qword [rbx + OP_KIND], OPK_IMM
    mov [rbx + OP_DISP], rax
    jmp .done
.memory:
    inc qword [rel forge_cur]
    mov rdi, rbx
    call forge_memory
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
.bad:
    lea rdi, [rel forge_msg_operands]
    jmp forge_fail

; name: forge_memory
; in:   rdi = operand, forge_cur after '['
; out:  memory operand parsed up to and past ']'
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_memory:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov qword [rbx + OP_KIND], OPK_MEM
    mov qword [rbx + OP_BASE], -1
    mov qword [rbx + OP_INDEX], -1
    mov qword [rbx + OP_SCALE], 1
    call forge_skip
    mov r12, [rel forge_cur]
    lea rdi, [rel forge_sym_word]
    call forge_ident
    lea rdi, [rel forge_sym_word]
    lea rsi, [rel forge_kw_rel]
    call str_eq
    jne .no_rel
    mov qword [rbx + OP_RIP], 1
    mov r12, [rel forge_cur]
.no_rel:
    mov [rel forge_cur], r12
    mov r13d, 1                     ; sign of the next term
.term:
    call forge_skip
    mov r12, [rel forge_cur]
    lea rdi, [rel forge_sym_word]
    call forge_ident
    test rax, rax
    jz .expression
    lea rdi, [rel forge_sym_word]
    call forge_register
    jc .expression
    cmp rdx, 8
    jne .bad
    cmp r13d, 1
    jne .bad
    mov r12, rax                    ; register number
    call forge_skip
    mov rax, [rel forge_cur]
    cmp byte [rax], '*'
    je .scaled
    cmp qword [rbx + OP_BASE], -1
    jne .as_index
    mov [rbx + OP_BASE], r12
    jmp .next
.as_index:
    cmp qword [rbx + OP_INDEX], -1
    jne .bad
    mov [rbx + OP_INDEX], r12
    jmp .next
.scaled:
    inc qword [rel forge_cur]
    cmp qword [rbx + OP_INDEX], -1
    jne .bad
    mov [rbx + OP_INDEX], r12
    call forge_factor
    mov [rbx + OP_SCALE], rax
    jmp .next
.expression:
    mov [rel forge_cur], r12
    call forge_term
    imul rax, r13
    add [rbx + OP_DISP], rax
.next:
    call forge_skip
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .bad
    movzx ecx, byte [rax]
    inc qword [rel forge_cur]
    mov r13d, 1
    cmp ecx, '+'
    je .term
    mov r13, -1
    cmp ecx, '-'
    je .term
    cmp ecx, ']'
    jne .bad
    mov rax, [rbx + OP_SCALE]       ; scale 1, 2, 4 or 8, kept as its log2
    bsf rcx, rax
    jz .bad
    mov eax, 1
    shl eax, cl
    cmp rax, [rbx + OP_SCALE]
    jne .bad
    cmp ecx, 3
    ja .bad
    mov [rbx + OP_SCALE], rcx
    cmp qword [rbx + OP_INDEX], 4   ; rsp cannot be an index
    je .bad
    cmp qword [rbx + OP_RIP], 0
    je .done
    cmp qword [rbx + OP_BASE], -1
    jne .bad
    cmp qword [rbx + OP_INDEX], -1
    jne .bad
.done:
    pop r13
    pop r12
    pop rbx
    ret
.bad:
    lea rdi, [rel forge_msg_memory]
    jmp forge_fail

; name: forge_register
; in:   rdi = name
; out:  rax = register number, rdx = size in bytes, CF=1 if not a register
; clobbers: rcx, rsi
forge_register:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    lea rbx, [rel forge_regs]
.next:
    cmp byte [rbx], 0
    je .missing
    mov rdi, r12
    mov rsi, rbx
    call str_eq
    je .found
    mov rdi, rbx
    call str_skip
    lea rbx, [rax + 2]
    jmp .next
.found:
    mov rdi, rbx
    call str_skip
    movzx edx, byte [rax + 1]
    movzx eax, byte [rax]
    add rsp, 8
    pop r12
    pop rbx
    clc
    ret
.missing:
    add rsp, 8
    pop r12
    pop rbx
    stc
    ret

; name: forge_size_keyword
; in:   rdi = name
; out:  rax = 1, 2, 4 or 8 for byte, word, dword, qword; CF=1 otherwise
; clobbers: rcx, rdx, rsi, rdi
forge_size_keyword:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    lea rbx, [rel forge_sizes]
.next:
    movzx eax, byte [rbx]
    test eax, eax
    jz .missing
    mov rdi, r12
    lea rsi, [rbx + 1]
    call str_eq
    je .found
    lea rdi, [rbx + 1]
    call str_skip
    mov rbx, rax
    jmp .next
.found:
    movzx eax, byte [rbx]
    add rsp, 8
    pop r12
    pop rbx
    clc
    ret
.missing:
    add rsp, 8
    pop r12
    pop rbx
    stc
    ret

forge_kw_rel db "rel", 0
forge_sizes  db 1, "byte", 0, 2, "word", 0, 4, "dword", 0, 8, "qword", 0, 0

; name, then register number and size
forge_regs:
    db "rax",0,0,8, "rcx",0,1,8, "rdx",0,2,8, "rbx",0,3,8
    db "rsp",0,4,8, "rbp",0,5,8, "rsi",0,6,8, "rdi",0,7,8
    db "r8",0,8,8, "r9",0,9,8, "r10",0,10,8, "r11",0,11,8
    db "r12",0,12,8, "r13",0,13,8, "r14",0,14,8, "r15",0,15,8
    db "eax",0,0,4, "ecx",0,1,4, "edx",0,2,4, "ebx",0,3,4
    db "esp",0,4,4, "ebp",0,5,4, "esi",0,6,4, "edi",0,7,4
    db "r8d",0,8,4, "r9d",0,9,4, "r10d",0,10,4, "r11d",0,11,4
    db "r12d",0,12,4, "r13d",0,13,4, "r14d",0,14,4, "r15d",0,15,4
    db "ax",0,0,2, "cx",0,1,2, "dx",0,2,2, "bx",0,3,2
    db "sp",0,4,2, "bp",0,5,2, "si",0,6,2, "di",0,7,2
    db "r8w",0,8,2, "r9w",0,9,2, "r10w",0,10,2, "r11w",0,11,2
    db "r12w",0,12,2, "r13w",0,13,2, "r14w",0,14,2, "r15w",0,15,2
    db "al",0,0,1, "cl",0,1,1, "dl",0,2,1, "bl",0,3,1
    db "spl",0,4,1, "bpl",0,5,1, "sil",0,6,1, "dil",0,7,1
    db "r8b",0,8,1, "r9b",0,9,1, "r10b",0,10,1, "r11b",0,11,1
    db "r12b",0,12,1, "r13b",0,13,1, "r14b",0,14,1, "r15b",0,15,1
    db 0

forge_msg_operands db "bad operands", 0
forge_msg_memory   db "bad memory reference", 0

section .bss
alignb 8
forge_ops      resb OP_SIZEOF * FORGE_OPS_MAX
forge_op_count resq 1
section .text
