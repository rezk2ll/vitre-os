; Poly1305 (RFC 8439) with the accumulator h in three 64-bit limbs, kept
; below about 2^131 between blocks and reduced mod 2^130 - 5 at the end.
; One MAC at a time: the state is global.

; name: poly1305_init
; in:   rdi = 32-byte one-time key
; out:  the MAC started
; clobbers: rax
poly1305_init:
    mov rax, 0x0ffffffc0fffffff     ; clamp r
    and rax, [rdi]
    mov [rel poly_r0], rax
    mov rax, 0x0ffffffc0ffffffc
    and rax, [rdi + 8]
    mov [rel poly_r1], rax
    shr rax, 2                      ; r1 * 5/4, exact as r1's low bits are 0
    add rax, [rel poly_r1]
    mov [rel poly_s1], rax
    mov rax, [rdi + 16]
    mov [rel poly_s], rax
    mov rax, [rdi + 24]
    mov [rel poly_s + 8], rax
    xor eax, eax
    mov [rel poly_h], rax
    mov [rel poly_h + 8], rax
    mov [rel poly_h + 16], rax
    ret

; name: poly1305_update
; in:   rsi = data, rdx = length, ecx = 1 to pad a last partial block with
;       zeros as the AEAD does, 0 to end it with the 0x01 byte of plain
;       Poly1305 (only the last call may have a partial block then)
; out:  the data mixed in
; clobbers: caller-saved
poly1305_update:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13, rdx
    mov ebp, ecx
    mov r8, [rel poly_h]
    mov r9, [rel poly_h + 8]
    mov r10, [rel poly_h + 16]
.block:
    cmp r13, 16
    jb .tail
    add r8, [r12]
    adc r9, [r12 + 8]
    adc r10, 1                      ; the 2^128 bit of a full block
    call poly1305_mul
    add r12, 16
    sub r13, 16
    jmp .block
.tail:
    test r13, r13
    jz .store
    xor eax, eax
    mov [rel poly_blk], rax
    mov [rel poly_blk + 8], rax
    lea rdi, [rel poly_blk]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    test ebp, ebp
    jnz .padded
    mov byte [rdi], 1
.padded:
    add r8, [rel poly_blk]
    adc r9, [rel poly_blk + 8]
    adc r10, rbp
    call poly1305_mul
.store:
    mov [rel poly_h], r8
    mov [rel poly_h + 8], r9
    mov [rel poly_h + 16], r10
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; name: poly1305_mul
; in:   r8, r9, r10 = h
; out:  h * r, partly reduced
; clobbers: rax, rbx, rcx, rdx, r14, r15
poly1305_mul:
    mov rax, r8                     ; d0 = h0 r0 + h1 s1
    mul qword [rel poly_r0]
    mov r14, rax
    mov r15, rdx
    mov rax, r9
    mul qword [rel poly_s1]
    add r14, rax
    adc r15, rdx
    mov rax, r8                     ; d1 = h0 r1 + h1 r0 + h2 s1
    mul qword [rel poly_r1]
    mov rbx, rax
    mov rcx, rdx
    mov rax, r9
    mul qword [rel poly_r0]
    add rbx, rax
    adc rcx, rdx
    mov rax, r10
    imul rax, [rel poly_s1]
    add rbx, rax
    adc rcx, 0
    imul r10, [rel poly_r0]         ; d2 = h2 r0
    mov r8, r14
    add rbx, r15
    adc rcx, 0
    mov r9, rbx
    add r10, rcx
    mov rax, r10                    ; fold the bits above 2^130 back as * 5
    shr rax, 2
    mov rdx, r10
    and rdx, -4
    add rax, rdx
    and r10, 3
    add r8, rax
    adc r9, 0
    adc r10, 0
    ret

; name: poly1305_final
; in:   rdi = 16-byte tag output
; out:  the tag written
; clobbers: rax, rcx, rdx, r8, r9
poly1305_final:
    mov r8, [rel poly_h]
    mov r9, [rel poly_h + 8]
    mov rax, r8                     ; h - p, if h >= p, is h + 5 - 2^130
    add rax, 5
    mov rdx, r9
    adc rdx, 0
    mov rcx, [rel poly_h + 16]
    adc rcx, 0
    shr rcx, 2
    jz .add
    mov r8, rax
    mov r9, rdx
.add:
    add r8, [rel poly_s]
    adc r9, [rel poly_s + 8]
    mov [rdi], r8
    mov [rdi + 8], r9
    ret

section .bss
alignb 8
poly_r0  resq 1
poly_r1  resq 1
poly_s1  resq 1
poly_h   resq 3
poly_s   resq 2
poly_blk resq 2
section .text
