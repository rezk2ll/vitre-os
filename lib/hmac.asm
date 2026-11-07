; HMAC-SHA256 (RFC 2104) and HKDF (RFC 5869) on top of it. Both keep their
; state in fixed buffers: one caller at a time.

HKDF_INFO_MAX equ 512

; name: hmac_sha256
; in:   rdi = key, esi = key length, rdx = message, rcx = message length,
;       r8 = 32-byte output (may overlap the message)
; out:  the MAC written
; clobbers: caller-saved
hmac_sha256:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    mov [rel hmac_out], r8
    lea rdi, [rel hmac_key]
    mov ecx, 64
    xor eax, eax
    rep stosb
    cmp r12d, 64
    ja .long
    lea rdi, [rel hmac_key]
    mov rsi, rbx
    mov ecx, r12d
    rep movsb
    jmp .inner
.long:
    lea rdi, [rel hmac_ctx]         ; a key longer than a block is hashed
    call sha256_init
    lea rdi, [rel hmac_ctx]
    mov rsi, rbx
    mov edx, r12d
    call sha256_update
    lea rdi, [rel hmac_ctx]
    lea rsi, [rel hmac_key]
    call sha256_final
.inner:
    mov bl, 0x36
    call hmac_start
    lea rdi, [rel hmac_ctx]
    mov rsi, r13
    mov rdx, r14
    call sha256_update
    lea rdi, [rel hmac_ctx]
    lea rsi, [rel hmac_inner]
    call sha256_final
    mov bl, 0x5c
    call hmac_start
    lea rdi, [rel hmac_ctx]
    lea rsi, [rel hmac_inner]
    mov edx, 32
    call sha256_update
    lea rdi, [rel hmac_ctx]
    mov rsi, [rel hmac_out]
    call sha256_final
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: hmac_start
; in:   bl = pad byte, hmac_key
; out:  hmac_ctx started with the key xor the pad
; clobbers: caller-saved except rbx
hmac_start:
    lea rdi, [rel hmac_block]
    lea rsi, [rel hmac_key]
    mov ecx, 64
.byte:
    lodsb
    xor al, bl
    stosb
    loop .byte
    lea rdi, [rel hmac_ctx]
    call sha256_init
    lea rdi, [rel hmac_ctx]
    lea rsi, [rel hmac_block]
    mov edx, 64
    jmp sha256_update

; name: hkdf_expand
; in:   rdi = 32-byte pseudorandom key, rsi = info, edx = info length (at
;       most HKDF_INFO_MAX), rcx = output, r8d = output length (at most
;       255 * 32)
; out:  the output keying material written
; clobbers: caller-saved
hkdf_expand:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, edx
    mov r13, rcx
    mov r14d, r8d
    lea rdi, [rel hkdf_msg + 32]    ; T(i-1), then info, then i
    mov ecx, edx
    rep movsb
    mov byte [rdi], 0
    lea rdx, [rel hkdf_msg + 32]    ; T(0) is empty
    lea ecx, [r12 + 1]
.block:
    test r14d, r14d
    jz .done
    lea rax, [rel hkdf_msg + 32]
    inc byte [rax + r12]
    mov rdi, rbx
    mov esi, 32
    lea r8, [rel hkdf_msg]
    call hmac_sha256
    mov ecx, 32
    cmp ecx, r14d
    cmova ecx, r14d
    sub r14d, ecx
    mov rdi, r13
    add r13, rcx
    lea rsi, [rel hkdf_msg]
    rep movsb
    lea rdx, [rel hkdf_msg]
    lea ecx, [r12 + 33]
    jmp .block
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .bss
alignb 8
hmac_out   resq 1
hmac_ctx   resb SHA_CTX_SIZE
hmac_key   resb 64
hmac_block resb 64
hmac_inner resb 32
hkdf_msg   resb 32 + HKDF_INFO_MAX + 1
section .text
