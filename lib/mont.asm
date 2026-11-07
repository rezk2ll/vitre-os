; Arithmetic modulo a 256-bit odd modulus above 2^255 (the P-256 prime
; and group order), on four little-endian 64-bit limbs. Products are in
; Montgomery form, a*R mod m with R = 2^256.

MM_MOD  equ 0                       ; a modulus: m,
MM_INV  equ 32                      ; -1/m mod 2^64,
MM_R2   equ 40                      ; R^2 mod m,
MM_ONE  equ 72                      ; R mod m,
MM_EXP  equ 104                     ; m - 2, the exponent of an inverse

; t_j += a_j * rbx + rbp, written to %3; rbp = the carry out
%macro MM_MAC 3
    mov rax, %1
    mul rbx
    add rax, %2
    adc rdx, 0
    add rax, rbp
    adc rdx, 0
    mov %3, rax
    mov rbp, rdx
%endmacro

; name: mm_mul
; in:   rdi = output, rsi = a, rdx = b, both below m; rcx = modulus
; out:  a*b/R mod m written; rdi may be rsi or rdx
; clobbers: rax, rcx, rdx, r8, r9, r10, r11
mm_mul:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r8, rdx
    mov r9, rcx
    xor r10d, r10d                  ; t, six limbs
    xor r11d, r11d
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    xor ecx, ecx
.limb:
    mov rbx, [r8 + rcx]             ; t += a * b_i
    xor ebp, ebp
    MM_MAC [rsi], r10, r10
    MM_MAC [rsi + 8], r11, r11
    MM_MAC [rsi + 16], r12, r12
    MM_MAC [rsi + 24], r13, r13
    add r14, rbp
    adc r15, 0
    mov rbx, r10                    ; t = (t + q*m) / 2^64, q zeroing t_0
    imul rbx, [r9 + MM_INV]
    xor ebp, ebp
    MM_MAC [r9], r10, r10
    MM_MAC [r9 + 8], r11, r10
    MM_MAC [r9 + 16], r12, r11
    MM_MAC [r9 + 24], r13, r12
    add r14, rbp
    mov r13, r14
    mov r14, r15
    adc r14, 0
    xor r15d, r15d
    add ecx, 8
    cmp ecx, 32
    jb .limb
    mov rax, r10                    ; t < 2m: take off m once if it fits
    sub rax, [r9]
    mov rbx, r11
    sbb rbx, [r9 + 8]
    mov rcx, r12
    sbb rcx, [r9 + 16]
    mov rdx, r13
    sbb rdx, [r9 + 24]
    sbb r14, 0
    cmovnc r10, rax
    cmovnc r11, rbx
    cmovnc r12, rcx
    cmovnc r13, rdx
    mov [rdi], r10
    mov [rdi + 8], r11
    mov [rdi + 16], r12
    mov [rdi + 24], r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; name: mm_add
; in:   rdi = output, rsi = a, rdx = b, both below m; rcx = modulus
; out:  a+b mod m written
; clobbers: rax, rdx, r8, r9, r10, r11
mm_add:
    mov r8, [rsi]
    add r8, [rdx]
    mov r9, [rsi + 8]
    adc r9, [rdx + 8]
    mov r10, [rsi + 16]
    adc r10, [rdx + 16]
    mov r11, [rsi + 24]
    adc r11, [rdx + 24]
    sbb rax, rax                    ; -1 if it carried past 2^256
    jmp mm_sub_m

; name: mm_sub
; in:   rdi = output, rsi = a, rdx = b, both below m; rcx = modulus
; out:  a-b mod m written
; clobbers: rax, rdx, r8, r9, r10, r11
mm_sub:
    mov r8, [rsi]
    sub r8, [rdx]
    mov r9, [rsi + 8]
    sbb r9, [rdx + 8]
    mov r10, [rsi + 16]
    sbb r10, [rdx + 16]
    mov r11, [rsi + 24]
    sbb r11, [rdx + 24]
    jnc mm_store
    add r8, [rcx]                   ; it went below 0: add m back
    adc r9, [rcx + 8]
    adc r10, [rcx + 16]
    adc r11, [rcx + 24]
    jmp mm_store

; name: mm_reduce
; in:   rdi = output, rsi = a below 2^256, rcx = modulus
; out:  a mod m written
; clobbers: rax, rdx, r8, r9, r10, r11
mm_reduce:
    mov r8, [rsi]
    mov r9, [rsi + 8]
    mov r10, [rsi + 16]
    mov r11, [rsi + 24]
    xor eax, eax
    ; fall through

; name: mm_sub_m
; in:   r8 to r11 = a value below 2m, rax = -1 if it has a 2^256 bit
;       else 0; rdi = output, rcx = modulus
; out:  it reduced below m and written
; clobbers: rax, rdx, r8, r9, r10, r11
mm_sub_m:
    push rbx
    push r12
    push r13
    mov rdx, r8
    sub rdx, [rcx]
    mov rbx, r9
    sbb rbx, [rcx + 8]
    mov r12, r10
    sbb r12, [rcx + 16]
    mov r13, r11
    sbb r13, [rcx + 24]
    sbb rax, 0                      ; borrows only if a < m
    cmovnc r8, rdx
    cmovnc r9, rbx
    cmovnc r10, r12
    cmovnc r11, r13
    pop r13
    pop r12
    pop rbx
mm_store:
    mov [rdi], r8
    mov [rdi + 8], r9
    mov [rdi + 16], r10
    mov [rdi + 24], r11
    ret

; name: mm_pow
; in:   rdi = output, rsi = a, rdx = exponent, rcx = modulus; a in
;       Montgomery form, the output not a
; out:  a^e written, in Montgomery form
; clobbers: rax, rcx, rdx, rsi, r8, r9, r10, r11
mm_pow:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rsi, [rcx + MM_ONE]
    mov rax, [rsi]                  ; start from 1
    mov [rdi], rax
    mov rax, [rsi + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    mov [rdi + 24], rax
    mov r15d, 255                   ; the bit, from the top
.bit:
    mov rdi, rbx
    mov rsi, rbx
    mov rdx, rbx
    mov rcx, r14
    call mm_mul
    mov eax, r15d
    shr eax, 6
    mov rax, [r13 + rax * 8]
    bt rax, r15
    jnc .next
    mov rdi, rbx
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r14
    call mm_mul
.next:
    dec r15d
    jns .bit
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: mm_inv
; in:   rdi = output, rsi = a in Montgomery form, not 0; rcx = modulus;
;       the output not a
; out:  1/a written, in Montgomery form
; clobbers: rax, rcx, rdx, rsi, r8, r9, r10, r11
mm_inv:
    lea rdx, [rcx + MM_EXP]
    jmp mm_pow

; name: mm_to
; in:   rdi = output, rsi = a below m, rcx = modulus
; out:  a in Montgomery form
; clobbers: rax, rcx, rdx, r8, r9, r10, r11
mm_to:
    lea rdx, [rcx + MM_R2]
    jmp mm_mul

; name: mm_from
; in:   rdi = output, rsi = a in Montgomery form, rcx = modulus
; out:  a out of Montgomery form
; clobbers: rax, rcx, rdx, r8, r9, r10, r11
mm_from:
    lea rdx, [rel mm_one]
    jmp mm_mul

; name: num_load
; in:   rdi = four limbs, rsi = 32 big-endian bytes
; out:  the number read into the limbs
; clobbers: rax
num_load:
    mov rax, [rsi + 24]
    bswap rax
    mov [rdi], rax
    mov rax, [rsi + 16]
    bswap rax
    mov [rdi + 8], rax
    mov rax, [rsi + 8]
    bswap rax
    mov [rdi + 16], rax
    mov rax, [rsi]
    bswap rax
    mov [rdi + 24], rax
    ret

; name: num_store
; in:   rdi = 32 bytes, rsi = four limbs
; out:  the number written big-endian
; clobbers: rax
num_store:
    jmp num_load                    ; the same byte reversal

align 8
mm_one  dq 1, 0, 0, 0
mm_p256 dq 0xffffffffffffffff, 0x00000000ffffffff, 0x0000000000000000, 0xffffffff00000001
        dq 0x0000000000000001
        dq 0x0000000000000003, 0xfffffffbffffffff, 0xfffffffffffffffe, 0x00000004fffffffd
        dq 0x0000000000000001, 0xffffffff00000000, 0xffffffffffffffff, 0x00000000fffffffe
        dq 0xfffffffffffffffd, 0x00000000ffffffff, 0x0000000000000000, 0xffffffff00000001
mm_n256 dq 0xf3b9cac2fc632551, 0xbce6faada7179e84, 0xffffffffffffffff, 0xffffffff00000000
        dq 0xccd1c8aaee00bc4f
        dq 0x83244c95be79eea2, 0x4699799c49bd6fa6, 0x2845b2392b6bec59, 0x66e12d94f3d95620
        dq 0x0c46353d039cdaaf, 0x4319055258e8617b, 0x0000000000000000, 0x00000000ffffffff
        dq 0xf3b9cac2fc63254f, 0xbce6faada7179e84, 0xffffffffffffffff, 0xffffffff00000000
