; X25519 (RFC 7748): the Montgomery ladder over GF(2^255 - 19). A field
; element is four little-endian 64-bit limbs holding a value below 2^256;
; it is reduced below p only for output. Since 2^256 = 38 mod p, a carry
; out of the top limb comes back as 38.

%macro FE 4                         ; %1 = op(%2 out, %3, %4)
    lea rdi, [rel %2]
    lea rsi, [rel %3]
    lea rdx, [rel %4]
    call %1
%endmacro

; name: fe_mul
; in:   rdi = out, rsi = a, rdx = b; out may be a or b
; out:  a * b
; clobbers: rax, rcx, rdx, rsi, r8-r11
fe_mul:
    push rbx
    push r12
    sub rsp, 64                     ; the 512-bit product
    mov r12, rdx
    xor eax, eax
    mov ecx, 8
.zero:
    mov [rsp + rcx * 8 - 8], rax
    loop .zero
    xor r8d, r8d
.row:
    xor r9d, r9d
    xor r10d, r10d
    mov r11, [rsi + r8 * 8]
.col:
    mov rax, r11
    mul qword [r12 + r9 * 8]
    add rax, r10
    adc rdx, 0
    lea rbx, [r8 + r9]
    add [rsp + rbx * 8], rax
    adc rdx, 0
    mov r10, rdx
    inc r9d
    cmp r9d, 4
    jb .col
    mov [rsp + r8 * 8 + 32], r10
    inc r8d
    cmp r8d, 4
    jb .row
    xor r10d, r10d                  ; low half + 38 * high half
    xor r8d, r8d
    mov ecx, 38
.fold:
    mov rax, [rsp + r8 * 8 + 32]
    mul rcx
    add rax, r10
    adc rdx, 0
    add rax, [rsp + r8 * 8]
    adc rdx, 0
    mov [rdi + r8 * 8], rax
    mov r10, rdx
    inc r8d
    cmp r8d, 4
    jb .fold
    imul r10, r10, 38
    add rsp, 64
    pop r12
    pop rbx
    jmp fe_carry

; name: fe_mul_a24
; in:   rdi = out, rsi = a
; out:  a * 121665, the ladder's (A - 2) / 4
; clobbers: rax, rcx, rdx, r8, r10
fe_mul_a24:
    xor r10d, r10d
    xor ecx, ecx
    mov r8d, 121665
.limb:
    mov rax, [rsi + rcx * 8]
    mul r8
    add rax, r10
    adc rdx, 0
    mov [rdi + rcx * 8], rax
    mov r10, rdx
    inc ecx
    cmp ecx, 4
    jb .limb
    imul r10, r10, 38
    jmp fe_carry

; name: fe_add
; in:   rdi = out, rsi = a, rdx = b; out may be a or b
; out:  a + b
; clobbers: rax, r10
fe_add:
    mov rax, [rsi]
    add rax, [rdx]
    mov [rdi], rax
    mov rax, [rsi + 8]
    adc rax, [rdx + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    adc rax, [rdx + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    adc rax, [rdx + 24]
    mov [rdi + 24], rax
    sbb r10, r10
    and r10d, 38
    ; fall through

; name: fe_carry
; in:   rdi = element, r10 = small amount to add
; out:  the amount added, a carry out of 2^256 folded back as 38
; clobbers: r10
fe_carry:
    add [rdi], r10
    adc qword [rdi + 8], 0
    adc qword [rdi + 16], 0
    adc qword [rdi + 24], 0
    sbb r10, r10
    and r10d, 38
    add [rdi], r10                  ; cannot carry: the limb just wrapped
    ret

; name: fe_sub
; in:   rdi = out, rsi = a, rdx = b; out may be a or b
; out:  a - b
; clobbers: rax, r10
fe_sub:
    mov rax, [rsi]
    sub rax, [rdx]
    mov [rdi], rax
    mov rax, [rsi + 8]
    sbb rax, [rdx + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    sbb rax, [rdx + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    sbb rax, [rdx + 24]
    mov [rdi + 24], rax
    sbb r10, r10                    ; a borrow of 2^256 is a borrow of 38
    and r10d, 38
    sub [rdi], r10
    sbb qword [rdi + 8], 0
    sbb qword [rdi + 16], 0
    sbb qword [rdi + 24], 0
    sbb r10, r10
    and r10d, 38
    sub [rdi], r10                  ; cannot borrow: the limb just wrapped
    ret

; name: fe_cswap
; in:   rdi, rsi = elements, rax = 0 to keep them or -1 to swap them
; out:  them swapped or not, with the same memory accesses either way
; clobbers: rcx, rdx, r8, r9
fe_cswap:
    mov ecx, 4
.limb:
    mov rdx, [rdi + rcx * 8 - 8]
    mov r8, [rsi + rcx * 8 - 8]
    mov r9, rdx
    xor r9, r8
    and r9, rax
    xor rdx, r9
    xor r8, r9
    mov [rdi + rcx * 8 - 8], rdx
    mov [rsi + rcx * 8 - 8], r8
    loop .limb
    ret

; name: fe_freeze
; in:   rdi = element
; out:  it reduced below p
; clobbers: rax, r8-r11
fe_freeze:
    mov rax, [rdi + 24]             ; fold bit 255 back as 19
    shr rax, 63
    btr qword [rdi + 24], 63
    imul rax, rax, 19
    add [rdi], rax
    adc qword [rdi + 8], 0
    adc qword [rdi + 16], 0
    adc qword [rdi + 24], 0
    mov r8, [rdi]                   ; now below 2^255 + 19: x - p = x + 19 - 2^255
    add r8, 19
    mov r9, [rdi + 8]
    adc r9, 0
    mov r10, [rdi + 16]
    adc r10, 0
    mov r11, [rdi + 24]
    adc r11, 0
    btr r11, 63
    jnc .done
    mov [rdi], r8
    mov [rdi + 8], r9
    mov [rdi + 16], r10
    mov [rdi + 24], r11
.done:
    ret

; name: x25519
; in:   rdi = 32-byte output, rsi = 32-byte scalar, rdx = 32-byte u
; out:  the scalar times the point u
; clobbers: caller-saved
x25519:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    lea rdi, [rel x_k]
    mov ecx, 32
    rep movsb
    and byte [rel x_k], 248
    and byte [rel x_k + 31], 127
    or byte [rel x_k + 31], 64
    lea rdi, [rel x_1]
    mov rsi, rdx
    mov ecx, 32
    rep movsb
    btr qword [rel x_1 + 24], 63
    xor eax, eax
    lea rdi, [rel x_2]              ; x_2 = 1, z_2 = 0, x_3 = u, z_3 = 1
    mov ecx, 16
    rep stosq
    mov byte [rel x_2], 1
    mov byte [rel z_3], 1
    lea rdi, [rel x_3]
    lea rsi, [rel x_1]
    mov ecx, 32
    rep movsb
    xor r13d, r13d                  ; the pending swap
    mov ebx, 254
.step:
    mov eax, ebx
    shr eax, 3
    lea rcx, [rel x_k]
    movzx r14d, byte [rcx + rax]
    mov ecx, ebx
    and ecx, 7
    shr r14d, cl
    and r14d, 1
    xor r13d, r14d
    call x_swap
    mov r13d, r14d
    FE fe_add, x_a, x_2, z_2
    FE fe_mul, x_aa, x_a, x_a
    FE fe_sub, x_b, x_2, z_2
    FE fe_mul, x_bb, x_b, x_b
    FE fe_sub, x_e, x_aa, x_bb
    FE fe_add, x_c, x_3, z_3
    FE fe_sub, x_d, x_3, z_3
    FE fe_mul, x_d, x_d, x_a        ; DA
    FE fe_mul, x_c, x_c, x_b        ; CB
    FE fe_add, x_3, x_d, x_c
    FE fe_mul, x_3, x_3, x_3
    FE fe_sub, z_3, x_d, x_c
    FE fe_mul, z_3, z_3, z_3
    FE fe_mul, z_3, x_1, z_3
    FE fe_mul, x_2, x_aa, x_bb
    lea rdi, [rel z_2]
    lea rsi, [rel x_e]
    call fe_mul_a24
    FE fe_add, z_2, x_aa, z_2
    FE fe_mul, z_2, x_e, z_2
    dec ebx
    jns .step
    call x_swap
    lea rdi, [rel x_a]              ; z_2^(p - 2), p - 2 = 2^255 - 21:
    mov qword [rdi], 1              ; every bit but 2 and 4 below 255
    xor eax, eax
    mov [rdi + 8], rax
    mov [rdi + 16], rax
    mov [rdi + 24], rax
    mov ebx, 254
.invert:
    FE fe_mul, x_a, x_a, x_a
    cmp ebx, 2
    je .square_only
    cmp ebx, 4
    je .square_only
    FE fe_mul, x_a, x_a, z_2
.square_only:
    dec ebx
    jns .invert
    FE fe_mul, x_2, x_2, x_a
    lea rdi, [rel x_2]
    call fe_freeze
    mov rdi, r12
    lea rsi, [rel x_2]
    mov ecx, 32
    rep movsb
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: x_swap
; in:   r13d = 1 to swap (x_2, z_2) with (x_3, z_3)
; out:  them swapped or not
; clobbers: rax, rcx, rdx, rsi, rdi, r8, r9
x_swap:
    mov eax, r13d
    neg rax
    lea rdi, [rel x_2]
    lea rsi, [rel x_3]
    call fe_cswap
    lea rdi, [rel z_2]
    lea rsi, [rel z_3]
    jmp fe_cswap

section .bss
alignb 8
x_2  resq 4                         ; x_2, z_2, x_3, z_3 in this order
z_2  resq 4
x_3  resq 4
z_3  resq 4
x_1  resq 4
x_k  resb 32
x_a  resq 4
x_aa resq 4
x_b  resq 4
x_bb resq 4
x_c  resq 4
x_d  resq 4
x_e  resq 4
section .text
