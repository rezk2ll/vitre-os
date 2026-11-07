; ChaCha20 (RFC 8439): a 32-byte key, a 32-bit block counter and a 96-bit
; nonce give a keystream that is xored into the data.

%macro CHACHA_QR 4                  ; the quarter round on words %1 to %4
    mov eax, [r10 + %1 * 4]
    mov ebx, [r10 + %2 * 4]
    mov ecx, [r10 + %3 * 4]
    mov edx, [r10 + %4 * 4]
    add eax, ebx
    xor edx, eax
    rol edx, 16
    add ecx, edx
    xor ebx, ecx
    rol ebx, 12
    add eax, ebx
    xor edx, eax
    rol edx, 8
    add ecx, edx
    xor ebx, ecx
    rol ebx, 7
    mov [r10 + %1 * 4], eax
    mov [r10 + %2 * 4], ebx
    mov [r10 + %3 * 4], ecx
    mov [r10 + %4 * 4], edx
%endmacro

; name: chacha20_block
; in:   rdi = 16-word state, rsi = 64-byte output
; out:  the state's keystream block written
; clobbers: rax, rcx, rdx, r8, r10, r11
chacha20_block:
    push rbx
    mov r10, rsi
    mov ecx, 16
.copy:
    mov eax, [rdi + rcx * 4 - 4]
    mov [r10 + rcx * 4 - 4], eax
    loop .copy
    mov r11d, 10
.round:
    CHACHA_QR 0, 4, 8, 12           ; columns
    CHACHA_QR 1, 5, 9, 13
    CHACHA_QR 2, 6, 10, 14
    CHACHA_QR 3, 7, 11, 15
    CHACHA_QR 0, 5, 10, 15          ; diagonals
    CHACHA_QR 1, 6, 11, 12
    CHACHA_QR 2, 7, 8, 13
    CHACHA_QR 3, 4, 9, 14
    dec r11d
    jnz .round
    xor r8d, r8d
.add:
    mov eax, [rdi + r8 * 4]
    add [r10 + r8 * 4], eax
    inc r8d
    cmp r8d, 16
    jb .add
    pop rbx
    ret

; name: chacha20_xor
; in:   rdi = 32-byte key, esi = first block counter, rdx = 12-byte nonce,
;       rcx = data, r8 = length, r9 = output (may be the data)
; out:  the data xored with the keystream into the output
; clobbers: caller-saved
chacha20_xor:
    push rbx
    push r12
    push r13
    mov r12, rcx
    mov r13, r8
    mov rbx, r9
    lea r10, [rel chacha_state]
    mov rax, [rel chacha_sigma]
    mov [r10], rax
    mov rax, [rel chacha_sigma + 8]
    mov [r10 + 8], rax
    xor ecx, ecx
.key:
    mov rax, [rdi + rcx * 8]
    mov [r10 + 16 + rcx * 8], rax
    inc ecx
    cmp ecx, 4
    jb .key
    mov [r10 + 48], esi
    mov rax, [rdx]
    mov [r10 + 52], rax
    mov eax, [rdx + 8]
    mov [r10 + 60], eax
.block:
    test r13, r13
    jz .done
    lea rdi, [rel chacha_state]
    lea rsi, [rel chacha_ks]
    call chacha20_block
    inc dword [rel chacha_state + 48]
    lea rdx, [rel chacha_ks]
    xor ecx, ecx
.byte:
    mov al, [r12 + rcx]
    xor al, [rdx + rcx]
    mov [rbx + rcx], al
    inc ecx
    dec r13
    jz .done
    cmp ecx, 64
    jb .byte
    add r12, 64
    add rbx, 64
    jmp .block
.done:
    pop r13
    pop r12
    pop rbx
    ret

chacha_sigma db "expand 32-byte k"

section .bss
alignb 8
chacha_state resd 16
chacha_ks    resb 64
section .text
