; Forge instruction encoding. An instruction is built in forge_ins, then
; flushed to the output; a RIP-relative displacement is filled in at the
; flush, when the instruction's length is known.

FORGE_INS_MAX equ 16

; name: forge_instruction
; in:   forge_word = mnemonic, forge_cur after it
; out:  one instruction emitted
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_instruction:
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [rel forge_word]
    lea rsi, [rel forge_mn_rep]
    call str_eq
    jne .lookup
    mov edi, 0xf3                   ; rep: prefix, then the string instruction
    call forge_emit_byte
    call forge_skip
    lea rdi, [rel forge_word]
    call forge_ident
.lookup:
    call forge_mnemonic
    mov rbx, rax                    ; handler
    mov r12, rdx                    ; its parameter
    call forge_operands
    mov qword [rel forge_ins_len], 0
    mov qword [rel forge_rip_pos], -1
    mov rdi, r12
    call rbx
    call forge_flush
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: forge_mnemonic
; in:   forge_word = mnemonic
; out:  rax = handler, rdx = its parameter; fails on an unknown mnemonic
; clobbers: rcx, rsi, rdi
forge_mnemonic:
    push rbx
    lea rbx, [rel forge_mnemonics]
.next:
    cmp qword [rbx], 0
    je .families
    lea rdi, [rel forge_word]
    lea rsi, [rbx + 10]
    call str_eq
    je .found
    lea rdi, [rbx + 10]
    call str_skip
    mov rbx, rax
    jmp .next
.found:
    mov rax, [rbx]
    movzx edx, word [rbx + 8]
    pop rbx
    ret
.families:                          ; jcc, setcc, cmovcc: prefix + condition
    lea rbx, [rel forge_families]
.family:
    cmp qword [rbx], 0
    je .unknown
    lea rdi, [rbx + 8]
    lea rsi, [rel forge_word]
.prefix:
    mov al, [rdi]
    test al, al
    jz .condition
    cmp al, [rsi]
    jne .next_family
    inc rdi
    inc rsi
    jmp .prefix
.condition:
    mov rdi, rsi
    call forge_condition
    jc .next_family
    mov rdx, rax
    mov rax, [rbx]
    pop rbx
    ret
.next_family:
    lea rdi, [rbx + 8]
    call str_skip
    mov rbx, rax
    jmp .family
.unknown:
    lea rdi, [rel forge_msg_mnemonic]
    jmp forge_fail

; name: forge_condition
; in:   rdi = condition suffix ("e", "nz", "ae", ...)
; out:  rax = condition code 0-15, CF=1 if it is not one
; clobbers: rcx, rdx, rsi, rdi
forge_condition:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    lea rbx, [rel forge_conditions]
.next:
    cmp byte [rbx], 0xff
    je .missing
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

; name: forge_ins_byte
; in:   dil = byte
; out:  byte appended to the instruction being built
; clobbers: rax
forge_ins_byte:
    mov rax, [rel forge_ins_len]
    cmp rax, FORGE_INS_MAX
    jae .long
    push rcx
    lea rcx, [rel forge_ins]
    mov [rcx + rax], dil
    pop rcx
    inc qword [rel forge_ins_len]
    ret
.long:
    lea rdi, [rel forge_msg_operands]
    jmp forge_fail

; name: forge_ins_value
; in:   rdi = value, rsi = byte count
; out:  bytes appended, little-endian
; clobbers: rax, rcx, rdi, rsi
forge_ins_value:
    mov rcx, rdi
.byte:
    mov edi, ecx
    call forge_ins_byte
    shr rcx, 8
    dec rsi
    jnz .byte
    ret

; name: forge_flush
; in:   forge_ins holds a whole instruction
; out:  RIP displacement filled in, bytes emitted
; clobbers: rax, rcx, rdx, rdi, rsi
forge_flush:
    push rbx
    mov rcx, [rel forge_rip_pos]
    test rcx, rcx
    js .emit
    mov rax, [rel forge_rip_target]
    sub rax, [rel forge_origin]
    sub rax, [rel forge_pc]
    sub rax, [rel forge_ins_len]
    movsxd rdx, eax
    cmp rdx, rax
    jne .far
    lea rdx, [rel forge_ins]
    mov [rdx + rcx], eax
.emit:
    xor ebx, ebx
.byte:
    cmp rbx, [rel forge_ins_len]
    jae .done
    lea rax, [rel forge_ins]
    movzx edi, byte [rax + rbx]
    call forge_emit_byte
    inc rbx
    jmp .byte
.done:
    pop rbx
    ret
.far:
    cmp qword [rel forge_pass], 1   ; addresses are not known yet
    je .emit
    lea rdi, [rel forge_msg_far]
    jmp forge_fail

; name: forge_size
; in:   forge_ops
; out:  rax = operand size: the first register operand's, else the memory
;       operand's keyword size; fails when neither gives one
; clobbers: rcx
forge_size:
    lea rcx, [rel forge_ops]
    mov rax, [rcx + OP_SIZE]
    cmp qword [rcx + OP_KIND], OPK_REG
    je .done
    cmp qword [rcx + OP_SIZEOF + OP_KIND], OPK_REG
    jne .first
    mov rax, [rcx + OP_SIZEOF + OP_SIZE]
.first:
    test rax, rax
    jnz .done
    lea rdi, [rel forge_msg_size]
    jmp forge_fail
.done:
    ret

; name: forge_fits8
; in:   rdi = immediate, rsi = operand size
; out:  ZF=1 if it fits a sign-extended byte at that size
; clobbers: rax, rdi
forge_fits8:
    cmp rsi, 4
    jne .not32
    movsxd rdi, edi
.not32:
    cmp rsi, 2
    jne .check
    movsx rdi, di
.check:
    movsx rax, dil
    cmp rax, rdi
    ret

; name: forge_imm
; in:   rdi = immediate, rsi = operand size (1, 2, 4; 8 is sent as 4)
; out:  immediate appended
; clobbers: rax, rcx, rdi, rsi
forge_imm:
    cmp rsi, 8
    jne forge_ins_value
    mov esi, 4
    jmp forge_ins_value

FORGE_OP1 equ 0
FORGE_OP2 equ OP_SIZEOF
FORGE_OP3 equ OP_SIZEOF * 2

%macro mnemonic 3
    dq %2
    dw %3
    db %1, 0
%endmacro

forge_mnemonics:
    mnemonic "mov", forge_enc_mov, 0
    mnemonic "lea", forge_enc_lea, 0
    mnemonic "add", forge_enc_alu, 0x00
    mnemonic "or", forge_enc_alu, 0x08
    mnemonic "and", forge_enc_alu, 0x20
    mnemonic "sub", forge_enc_alu, 0x28
    mnemonic "xor", forge_enc_alu, 0x30
    mnemonic "cmp", forge_enc_alu, 0x38
    mnemonic "test", forge_enc_test, 0
    mnemonic "inc", forge_enc_unary, 0xfe00
    mnemonic "dec", forge_enc_unary, 0xfe01
    mnemonic "not", forge_enc_unary, 0xf602
    mnemonic "neg", forge_enc_unary, 0xf603
    mnemonic "mul", forge_enc_unary, 0xf604
    mnemonic "div", forge_enc_unary, 0xf606
    mnemonic "idiv", forge_enc_unary, 0xf607
    mnemonic "imul", forge_enc_imul, 0
    mnemonic "shl", forge_enc_shift, 4
    mnemonic "shr", forge_enc_shift, 5
    mnemonic "sar", forge_enc_shift, 7
    mnemonic "push", forge_enc_push, 0x50
    mnemonic "pop", forge_enc_push, 0x58
    mnemonic "call", forge_enc_call, 0
    mnemonic "jmp", forge_enc_call, 1
    mnemonic "ret", forge_ins_byte, 0xc3
    mnemonic "nop", forge_ins_byte, 0x90
    mnemonic "movsb", forge_ins_byte, 0xa4
    mnemonic "stosb", forge_ins_byte, 0xaa
    mnemonic "movzx", forge_enc_movx, 0xb6
    mnemonic "movsx", forge_enc_movx, 0xbe
    mnemonic "movsxd", forge_enc_movsxd, 0
    dq 0

; handler, then the mnemonic prefix that a condition suffix follows
forge_families:
    dq forge_enc_jcc
    db "j", 0
    dq forge_enc_setcc
    db "set", 0
    dq forge_enc_cmovcc
    db "cmov", 0
    dq 0

forge_conditions:
    db 0, "o", 0, 1, "no", 0, 2, "b", 0, 2, "c", 0, 2, "nae", 0
    db 3, "ae", 0, 3, "nb", 0, 3, "nc", 0, 4, "e", 0, 4, "z", 0
    db 5, "ne", 0, 5, "nz", 0, 6, "be", 0, 6, "na", 0, 7, "a", 0
    db 7, "nbe", 0, 8, "s", 0, 9, "ns", 0, 10, "p", 0, 10, "pe", 0
    db 11, "np", 0, 11, "po", 0, 12, "l", 0, 12, "nge", 0, 13, "ge", 0
    db 13, "nl", 0, 14, "le", 0, 14, "ng", 0, 15, "g", 0, 15, "nle", 0
    db 0xff

forge_mn_rep db "rep", 0
forge_msg_mnemonic db "unknown instruction", 0
forge_msg_far      db "RIP-relative target out of range", 0
forge_msg_size     db "operand size unknown", 0

section .bss
alignb 8
forge_ins_len    resq 1
forge_rip_pos    resq 1
forge_rip_target resq 1
forge_ins        resb FORGE_INS_MAX
section .text
