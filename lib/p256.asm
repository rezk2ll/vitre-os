; ECDSA verification on P-256 (FIPS 186-4), for TLS certificates. Field
; values are in Montgomery form mod p; points are Jacobian X, Y, Z with
; Z = 0 for the point at infinity. Not constant time: it only checks
; public signatures.

EC_X equ 0
EC_Y equ 32
EC_Z equ 64
EC_POINT equ 96

%macro FMUL 3
    lea rdi, [rel %1]
    lea rsi, [rel %2]
    lea rdx, [rel %3]
    lea rcx, [rel mm_p256]
    call mm_mul
%endmacro

%macro FADD 3
    lea rdi, [rel %1]
    lea rsi, [rel %2]
    lea rdx, [rel %3]
    lea rcx, [rel mm_p256]
    call mm_add
%endmacro

%macro FSUB 3
    lea rdi, [rel %1]
    lea rsi, [rel %2]
    lea rdx, [rel %3]
    lea rcx, [rel mm_p256]
    call mm_sub
%endmacro

; name: ecdsa_verify
; in:   rdi = public key x then y, rsi = 32-byte hash, rdx = signature r
;       then s; all big-endian 32-byte numbers
; out:  CF=1 unless the signature is valid for the hash and key
; clobbers: caller-saved
ecdsa_verify:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rel ec_sr]
    mov rsi, r13
    call num_load
    lea rdi, [rel ec_ss]
    lea rsi, [r13 + 32]
    call num_load
    lea rsi, [rel ec_sr]
    lea rcx, [rel mm_n256]
    call ec_scalar_ok
    jc .done
    lea rsi, [rel ec_ss]
    call ec_scalar_ok
    jc .done
    lea rdi, [rel ec_t0]            ; the hash, mod n
    mov rsi, r12
    call num_load
    lea rdi, [rel ec_t0]
    lea rsi, [rel ec_t0]
    lea rcx, [rel mm_n256]
    call mm_reduce
    lea r13, [rel mm_n256]          ; u1 = e/s and u2 = r/s, mod n
    lea rdi, [rel ec_t1]
    lea rsi, [rel ec_ss]
    mov rcx, r13
    call mm_to
    lea rdi, [rel ec_t2]
    lea rsi, [rel ec_t1]
    mov rcx, r13
    call mm_inv
    lea rdi, [rel ec_u1]
    lea rsi, [rel ec_t0]
    lea rdx, [rel ec_t2]
    mov rcx, r13
    call mm_mul
    lea rdi, [rel ec_u2]
    lea rsi, [rel ec_sr]
    lea rdx, [rel ec_t2]
    mov rcx, r13
    call mm_mul
    mov rdi, rbx
    call ec_load_key
    jc .done
    call ec_table
    call ec_mul2
    call ec_affine_x
    jc .done
    lea rdi, [rel ec_t1]            ; x mod n, against r
    mov rsi, rdi
    lea rcx, [rel mm_n256]
    call mm_reduce
    lea rsi, [rel ec_t1]
    lea rdi, [rel ec_sr]
    mov ecx, 32
    repe cmpsb
    je .done                        ; CF=0 from the compare
.bad:
    stc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: ec_affine_x
; in:   ec_r
; out:  ec_t1 = its affine x, X/Z^2, out of Montgomery form; CF=1 if it
;       is the point at infinity
; clobbers: caller-saved
ec_affine_x:
    sub rsp, 8
    lea rsi, [rel ec_r + EC_Z]
    call ec_is_zero
    stc
    je .done
    lea rdi, [rel ec_t0]
    lea rsi, [rel ec_r + EC_Z]
    lea rcx, [rel mm_p256]
    call mm_inv
    FMUL ec_t1, ec_t0, ec_t0
    FMUL ec_t1, ec_t1, ec_r + EC_X
    lea rdi, [rel ec_t1]
    mov rsi, rdi
    lea rcx, [rel mm_p256]
    call mm_from
    clc
.done:
    lea rsp, [rsp + 8]
    ret

; name: ec_scalar_ok
; in:   rsi = four limbs, rcx = modulus
; out:  CF=1 unless 0 < the number < the modulus
; clobbers: rax
ec_scalar_ok:
    call ec_is_zero
    je .bad
    mov rax, [rsi]
    sub rax, [rcx]
    mov rax, [rsi + 8]
    sbb rax, [rcx + 8]
    mov rax, [rsi + 16]
    sbb rax, [rcx + 16]
    mov rax, [rsi + 24]
    sbb rax, [rcx + 24]
    cmc                             ; a borrow means below
    ret
.bad:
    stc
    ret

; name: ec_is_zero
; in:   rsi = four limbs
; out:  ZF=1 if they are all 0
; clobbers: rax
ec_is_zero:
    mov rax, [rsi]
    or rax, [rsi + 8]
    or rax, [rsi + 16]
    or rax, [rsi + 24]
    ret

; name: ec_load_key
; in:   rdi = public key x then y, big-endian
; out:  it in the table's second point, in Montgomery form; CF=1 if it is
;       not on the curve
; clobbers: caller-saved
ec_load_key:
    push rbx
    mov rbx, rdi
    lea rdi, [rel ec_q + EC_X]
    mov rsi, rbx
    call num_load
    lea rdi, [rel ec_q + EC_Y]
    lea rsi, [rbx + 32]
    call num_load
    lea rsi, [rel ec_q + EC_X]
    lea rcx, [rel mm_p256]
    call ec_scalar_ok               ; x = 0 is not on the curve either
    jc .done
    lea rsi, [rel ec_q + EC_Y]
    call ec_scalar_ok
    jc .done
    lea rdi, [rel ec_q + EC_X]
    mov rsi, rdi
    lea rcx, [rel mm_p256]
    call mm_to
    lea rdi, [rel ec_q + EC_Y]
    mov rsi, rdi
    lea rcx, [rel mm_p256]
    call mm_to
    lea rdi, [rel ec_q + EC_Z]
    lea rsi, [rel mm_p256 + MM_ONE]
    mov ecx, 32
    rep movsb
    FMUL ec_t0, ec_q + EC_X, ec_q + EC_X    ; y^2 = x^3 - 3x + b
    FMUL ec_t0, ec_t0, ec_q + EC_X
    FADD ec_t1, ec_q + EC_X, ec_q + EC_X
    FADD ec_t1, ec_t1, ec_q + EC_X
    FSUB ec_t0, ec_t0, ec_t1
    FADD ec_t0, ec_t0, ec_b
    FMUL ec_t1, ec_q + EC_Y, ec_q + EC_Y
    lea rsi, [rel ec_t0]
    lea rdi, [rel ec_t1]
    mov ecx, 32
    repe cmpsb
    je .done
    stc
.done:
    pop rbx
    ret

; name: ec_table
; in:   ec_q
; out:  ec_g holding G, ec_gq holding G + Q
; clobbers: caller-saved
ec_table:
    sub rsp, 8
    lea rdi, [rel ec_g]
    lea rsi, [rel ec_base]
    mov ecx, EC_POINT
    rep movsb
    lea rdi, [rel ec_r]
    lea rsi, [rel ec_base]
    mov ecx, EC_POINT
    rep movsb
    lea rdi, [rel ec_o]
    lea rsi, [rel ec_q]
    mov ecx, EC_POINT
    rep movsb
    call ec_add
    lea rdi, [rel ec_gq]
    lea rsi, [rel ec_r]
    mov ecx, EC_POINT
    rep movsb
    add rsp, 8
    ret

; name: ec_mul2
; in:   ec_u1, ec_u2, and the table of G, Q, G + Q
; out:  ec_r = u1*G + u2*Q, both bits of each step added at once
; clobbers: caller-saved
ec_mul2:
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [rel ec_r]
    xor eax, eax
    mov ecx, EC_POINT
    rep stosb
    mov ebx, 255
.bit:
    call ec_double
    mov eax, ebx
    shr eax, 6
    lea rdx, [rel ec_u1]
    mov rcx, [rdx + rax * 8]
    lea rdx, [rel ec_u2]
    mov rdx, [rdx + rax * 8]
    xor r12d, r12d
    bt rcx, rbx
    adc r12d, 0
    bt rdx, rbx
    jnc .one
    add r12d, 2
.one:
    test r12d, r12d
    jz .next
    imul esi, r12d, EC_POINT        ; G, Q and G + Q follow each other
    lea rax, [rel ec_g - EC_POINT]
    add rsi, rax
    lea rdi, [rel ec_o]
    mov ecx, EC_POINT
    rep movsb
    call ec_add
.next:
    dec ebx
    jns .bit
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: ec_double
; in:   ec_r
; out:  ec_r doubled (dbl-2001-b, for a = -3); infinity stays infinity
; clobbers: caller-saved
ec_double:
    sub rsp, 8
    FMUL ec_t0, ec_r + EC_Z, ec_r + EC_Z    ; delta
    FMUL ec_t1, ec_r + EC_Y, ec_r + EC_Y    ; gamma
    FMUL ec_t2, ec_r + EC_X, ec_t1          ; beta
    FSUB ec_t3, ec_r + EC_X, ec_t0
    FADD ec_t4, ec_r + EC_X, ec_t0
    FMUL ec_t3, ec_t3, ec_t4
    FADD ec_t4, ec_t3, ec_t3
    FADD ec_t4, ec_t4, ec_t3                ; alpha
    FMUL ec_t5, ec_t4, ec_t4
    FADD ec_t6, ec_t2, ec_t2
    FADD ec_t6, ec_t6, ec_t6                ; 4 beta
    FADD ec_t7, ec_t6, ec_t6
    FSUB ec_r + EC_X, ec_t5, ec_t7
    FADD ec_t5, ec_r + EC_Y, ec_r + EC_Z
    FMUL ec_t5, ec_t5, ec_t5
    FSUB ec_t5, ec_t5, ec_t1
    FSUB ec_r + EC_Z, ec_t5, ec_t0
    FSUB ec_t6, ec_t6, ec_r + EC_X
    FMUL ec_t6, ec_t4, ec_t6
    FMUL ec_t1, ec_t1, ec_t1
    FADD ec_t1, ec_t1, ec_t1
    FADD ec_t1, ec_t1, ec_t1
    FADD ec_t1, ec_t1, ec_t1                ; 8 gamma^2
    FSUB ec_r + EC_Y, ec_t6, ec_t1
    add rsp, 8
    ret

; name: ec_add
; in:   ec_r, ec_o
; out:  ec_r = ec_r + ec_o (add-2007-bl), doubling or infinity when the
;       x coordinates match
; clobbers: caller-saved
ec_add:
    sub rsp, 8
    lea rsi, [rel ec_o + EC_Z]
    call ec_is_zero
    je .done
    lea rsi, [rel ec_r + EC_Z]
    call ec_is_zero
    jne .both
    lea rdi, [rel ec_r]
    lea rsi, [rel ec_o]
    mov ecx, EC_POINT
    rep movsb
    jmp .done
.both:
    FMUL ec_t0, ec_r + EC_Z, ec_r + EC_Z    ; Z1Z1
    FMUL ec_t1, ec_o + EC_Z, ec_o + EC_Z    ; Z2Z2
    FMUL ec_t2, ec_r + EC_X, ec_t1          ; U1
    FMUL ec_t3, ec_o + EC_X, ec_t0          ; U2
    FMUL ec_t4, ec_r + EC_Y, ec_o + EC_Z
    FMUL ec_t4, ec_t4, ec_t1                ; S1
    FMUL ec_t5, ec_o + EC_Y, ec_r + EC_Z
    FMUL ec_t5, ec_t5, ec_t0                ; S2
    FSUB ec_t3, ec_t3, ec_t2                ; H
    FSUB ec_t5, ec_t5, ec_t4
    lea rsi, [rel ec_t3]
    call ec_is_zero
    jne .distinct
    lea rsi, [rel ec_t5]
    call ec_is_zero
    jne .infinity
    add rsp, 8
    jmp ec_double                   ; the same point
.infinity:
    lea rdi, [rel ec_r + EC_Z]
    xor eax, eax
    mov ecx, 32
    rep stosb
    jmp .done
.distinct:
    FADD ec_t5, ec_t5, ec_t5                ; r
    FADD ec_t6, ec_t3, ec_t3
    FMUL ec_t6, ec_t6, ec_t6                ; I
    FMUL ec_t7, ec_t3, ec_t6                ; J
    FMUL ec_t2, ec_t2, ec_t6                ; V
    FADD ec_t6, ec_r + EC_Z, ec_o + EC_Z
    FMUL ec_t6, ec_t6, ec_t6
    FSUB ec_t6, ec_t6, ec_t0
    FSUB ec_t6, ec_t6, ec_t1
    FMUL ec_r + EC_Z, ec_t6, ec_t3
    FMUL ec_t0, ec_t5, ec_t5
    FSUB ec_t0, ec_t0, ec_t7
    FSUB ec_t0, ec_t0, ec_t2
    FSUB ec_r + EC_X, ec_t0, ec_t2
    FSUB ec_t1, ec_t2, ec_r + EC_X
    FMUL ec_t1, ec_t5, ec_t1
    FMUL ec_t4, ec_t4, ec_t7
    FADD ec_t4, ec_t4, ec_t4
    FSUB ec_r + EC_Y, ec_t1, ec_t4
.done:
    add rsp, 8
    ret

align 8
ec_base dq 0x79e730d418a9143c, 0x75ba95fc5fedb601, 0x79fb732b77622510, 0x18905f76a53755c6
        dq 0xddf25357ce95560a, 0x8b4ab8e4ba19e45c, 0xd2e88688dd21f325, 0x8571ff1825885d85
        dq 0x0000000000000001, 0xffffffff00000000, 0xffffffffffffffff, 0x00000000fffffffe
ec_b    dq 0xd89cdf6229c4bddf, 0xacf005cd78843090, 0xe5a220abf7212ed6, 0xdc30061d04874834

section .bss
alignb 8
ec_g  resb EC_POINT                 ; G, Q and G + Q, in this order
ec_q  resb EC_POINT
ec_gq resb EC_POINT
ec_r  resb EC_POINT
ec_o  resb EC_POINT
ec_sr resq 4
ec_ss resq 4
ec_u1 resq 4
ec_u2 resq 4
ec_t0 resq 4
ec_t1 resq 4
ec_t2 resq 4
ec_t3 resq 4
ec_t4 resq 4
ec_t5 resq 4
ec_t6 resq 4
ec_t7 resq 4
section .text
