; ChaCha20-Poly1305 (RFC 8439 section 2.8), in place: sealing encrypts the
; data and writes the 16-byte tag after it; opening checks that tag before
; it decrypts anything.

; name: aead_seal
; in:   rdi = 32-byte key, rsi = 12-byte nonce, rdx = additional data,
;       ecx = its length, r8 = data, r9 = its length
; out:  the data encrypted, the tag written at r8 + r9
; clobbers: caller-saved
aead_seal:
    sub rsp, 8
    call aead_start
    call aead_crypt
    call aead_mac
    mov rdi, [rel aead_data]
    add rdi, [rel aead_len]
    lea rsi, [rel aead_tag]
    mov ecx, 16
    rep movsb
    add rsp, 8
    ret

; name: aead_open
; in:   as aead_seal, with the tag at r8 + r9
; out:  CF=0 and the data decrypted, or CF=1 and the data untouched if
;       the tag does not match
; clobbers: caller-saved
aead_open:
    sub rsp, 8
    call aead_start
    call aead_mac
    mov rsi, [rel aead_data]
    add rsi, [rel aead_len]
    lea rdi, [rel aead_tag]
    xor eax, eax                    ; every byte compared: no early exit
    xor ecx, ecx
.compare:
    mov dl, [rsi + rcx]
    xor dl, [rdi + rcx]
    or al, dl
    inc ecx
    cmp ecx, 16
    jb .compare
    test al, al
    jnz .bad
    call aead_crypt
    add rsp, 8
    clc
    ret
.bad:
    add rsp, 8
    stc
    ret

; name: aead_start
; in:   aead_seal's arguments
; out:  them saved, the Poly1305 key made from block 0, the additional
;       data and its padding hashed
; clobbers: caller-saved
aead_start:
    mov [rel aead_key], rdi
    mov [rel aead_nonce], rsi
    mov [rel aead_data], r8
    mov [rel aead_len], r9
    mov ecx, ecx
    mov [rel aead_lens], rcx
    mov [rel aead_lens + 8], r9
    push rdx
    xor eax, eax
    lea rdi, [rel aead_otk]
    mov ecx, 32
    rep stosb
    mov rdi, [rel aead_key]
    xor esi, esi
    mov rdx, [rel aead_nonce]
    lea rcx, [rel aead_otk]
    mov r8d, 32
    mov r9, rcx
    call chacha20_xor
    lea rdi, [rel aead_otk]
    call poly1305_init
    pop rsi
    mov rdx, [rel aead_lens]
    mov ecx, 1
    jmp poly1305_update

; name: aead_crypt
; in:   aead_start's state
; out:  the data xored with the keystream from block 1
; clobbers: caller-saved
aead_crypt:
    mov rdi, [rel aead_key]
    mov esi, 1
    mov rdx, [rel aead_nonce]
    mov rcx, [rel aead_data]
    mov r8, [rel aead_len]
    mov r9, rcx
    jmp chacha20_xor

; name: aead_mac
; in:   aead_start's state, the data encrypted
; out:  aead_tag over the ciphertext, its padding and both lengths
; clobbers: caller-saved
aead_mac:
    sub rsp, 8
    mov rsi, [rel aead_data]
    mov rdx, [rel aead_len]
    mov ecx, 1
    call poly1305_update
    lea rsi, [rel aead_lens]
    mov edx, 16
    mov ecx, 1
    call poly1305_update
    lea rdi, [rel aead_tag]
    add rsp, 8
    jmp poly1305_final

section .bss
alignb 8
aead_key   resq 1
aead_nonce resq 1
aead_data  resq 1
aead_len   resq 1
aead_lens  resq 2
aead_otk   resb 32
aead_tag   resb 16
section .text
