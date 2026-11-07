; TLS 1.3 client (RFC 8446) over the one TCP connection, offering only
; TLS_CHACHA20_POLY1305_SHA256 and X25519.

; name: tls_expand_label
; in:   rdi = secret, rsi = label without "tls13 " (at most 32 bytes),
;       rdx = context, ecx = its length (at most 32), r8 = output,
;       r9d = its length
; out:  HKDF-Expand-Label written
; clobbers: caller-saved
tls_expand_label:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, r8
    mov r13d, r9d
    mov r10, rdx
    mov r11d, ecx
    lea rdi, [rel tls_label]
    mov eax, r13d
    call tls_put16
    mov r8, rdi                     ; the label's length goes here
    inc rdi
    mov r9, rsi
    lea rsi, [rel tls_prefix]
    mov ecx, 6
    rep movsb
    mov rsi, r9
.label:
    lodsb
    test al, al
    jz .context
    stosb
    jmp .label
.context:
    mov rax, rdi
    sub rax, r8
    dec eax
    mov [r8], al
    mov eax, r11d
    stosb
    mov rsi, r10
    mov ecx, r11d
    rep movsb
    lea rsi, [rel tls_label]
    mov rdx, rdi
    sub rdx, rsi
    mov rdi, rbx
    mov rcx, r12
    mov r8d, r13d
    call hkdf_expand
    pop r13
    pop r12
    pop rbx
    ret

; name: tls_put16
; in:   rdi = position, eax = value
; out:  it stored big-endian, rdi past it
; clobbers: rax
tls_put16:
    xchg al, ah
    stosw
    ret

tls_prefix db "tls13 "

section .bss
tls_label resb 2 + 1 + 6 + 32 + 1 + 32
section .text
