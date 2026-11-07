; SHA-256 (FIPS 180-4), incremental: init, update any number of times,
; final. A context can be copied to hash a prefix and keep going, which is
; how TLS takes transcript hashes.

SHA_H        equ 0                  ; 8 state words
SHA_LEN      equ 32                 ; bytes hashed so far
SHA_BUF      equ 40                 ; a partial block
SHA_FILL     equ 104                ; bytes in it
SHA_CTX_SIZE equ 112

; name: sha256_init
; in:   rdi = context
; out:  the context ready for sha256_update
; clobbers: rcx, rsi, rdi
sha256_init:
    lea rsi, [rel sha256_iv]
    mov ecx, 32
    rep movsb
    mov qword [rdi + SHA_LEN - 32], 0
    mov dword [rdi + SHA_FILL - 32], 0
    ret

; name: sha256_update
; in:   rdi = context, rsi = data, rdx = length
; out:  the data hashed in
; clobbers: caller-saved
sha256_update:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    add [rbx + SHA_LEN], rdx
.next:
    test r13, r13
    jz .done
    mov eax, [rbx + SHA_FILL]
    mov ecx, 64
    sub ecx, eax                    ; room left in the block
    cmp rcx, r13
    cmova rcx, r13
    lea rdi, [rbx + SHA_BUF + rax]
    mov rsi, r12
    add r12, rcx
    sub r13, rcx
    add eax, ecx
    mov [rbx + SHA_FILL], eax
    rep movsb
    cmp eax, 64
    jne .next
    mov rdi, rbx
    lea rsi, [rbx + SHA_BUF]
    call sha256_block
    mov dword [rbx + SHA_FILL], 0
    jmp .next
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: sha256_final
; in:   rdi = context, rsi = 32-byte output
; out:  the digest written; the context is used up
; clobbers: caller-saved
sha256_final:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + SHA_LEN]
    shl rax, 3
    bswap rax
    push rax                        ; the length in bits, big-endian
    mov edx, 119                    ; 0x80, then zeros up to 56 mod 64
    sub edx, [rbx + SHA_FILL]
    and edx, 63
    inc edx
    lea rsi, [rel sha256_pad]
    call sha256_update
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 8
    call sha256_update
    pop rax
    xor ecx, ecx
.out:
    mov eax, [rbx + rcx * 4]
    bswap eax
    mov [r12 + rcx * 4], eax
    inc ecx
    cmp ecx, 8
    jb .out
    pop r12
    pop rbx
    ret

; name: sha256_block
; in:   rdi = context, rsi = 64-byte block
; out:  the block mixed into the state
; clobbers: rax, rcx, rdx, rsi, r8-r11
sha256_block:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                    ; the message schedule
    xor ecx, ecx
.load:
    mov eax, [rsi + rcx * 4]
    bswap eax
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 16
    jb .load
.expand:
    mov eax, [rsp + rcx * 4 - 8]    ; s1(w[i-2])
    mov edx, eax
    ror eax, 17
    mov r8d, edx
    ror r8d, 19
    xor eax, r8d
    shr edx, 10
    xor eax, edx
    add eax, [rsp + rcx * 4 - 28]   ; w[i-7]
    mov edx, [rsp + rcx * 4 - 60]   ; s0(w[i-15])
    mov r8d, edx
    ror r8d, 7
    mov r9d, edx
    ror r9d, 18
    xor r8d, r9d
    shr edx, 3
    xor r8d, edx
    add eax, r8d
    add eax, [rsp + rcx * 4 - 64]   ; w[i-16]
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 64
    jb .expand
    mov r8d, [rdi]                  ; a to h in r8 to r15
    mov r9d, [rdi + 4]
    mov r10d, [rdi + 8]
    mov r11d, [rdi + 12]
    mov r12d, [rdi + 16]
    mov r13d, [rdi + 20]
    mov r14d, [rdi + 24]
    mov r15d, [rdi + 28]
    lea rsi, [rel sha256_k]
    xor ecx, ecx
.round:
    mov eax, r12d                   ; t1 = h + S1(e) + Ch(e, f, g) + k + w
    ror eax, 6
    mov ebx, r12d
    ror ebx, 11
    xor eax, ebx
    ror ebx, 14
    xor eax, ebx
    mov ebx, r13d
    xor ebx, r14d
    and ebx, r12d
    xor ebx, r14d
    add eax, ebx
    add eax, r15d
    add eax, [rsi + rcx * 4]
    add eax, [rsp + rcx * 4]
    mov edx, r8d                    ; t2 = S0(a) + Maj(a, b, c)
    ror edx, 2
    mov ebx, r8d
    ror ebx, 13
    xor edx, ebx
    ror ebx, 9
    xor edx, ebx
    mov ebx, r8d
    or ebx, r9d
    and ebx, r10d
    mov ebp, r8d
    and ebp, r9d
    or ebx, ebp
    add edx, ebx
    mov r15d, r14d
    mov r14d, r13d
    mov r13d, r12d
    lea r12d, [r11 + rax]
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, r8d
    lea r8d, [rax + rdx]
    inc ecx
    cmp ecx, 64
    jb .round
    add [rdi], r8d
    add [rdi + 4], r9d
    add [rdi + 8], r10d
    add [rdi + 12], r11d
    add [rdi + 16], r12d
    add [rdi + 20], r13d
    add [rdi + 24], r14d
    add [rdi + 28], r15d
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

sha256_iv dd 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

sha256_k:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

sha256_pad db 0x80
           times 63 db 0
