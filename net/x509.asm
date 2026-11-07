; X.509 certificates (RFC 5280), DER read in place: only the parts a chain
; check needs. A parsed certificate is a record of X5_SIZE bytes.

X5_TBS      equ 0                   ; the signed part, as a whole element
X5_TBS_LEN  equ 8
X5_ISSUER   equ 16                  ; issuer and subject names, likewise
X5_ISS_LEN  equ 24
X5_SUBJECT  equ 32
X5_SUB_LEN  equ 40
X5_ALG      equ 60                  ; X5_ECDSA_SHA256, X5_ECDSA_SHA384 or 0
X5_KEYOK    equ 61                  ; 1 if the key is a P-256 one
X5_KEY      equ 64                  ; its x then y
X5_SIG      equ 128                 ; the signature's r then s
X5_SIZE     equ 192

X5_ECDSA_SHA256 equ 1
X5_ECDSA_SHA384 equ 2

; name: der_read
; in:   rsi = an element, rdx = where its enclosing data ends
; out:  al = its tag, rsi = its content, ecx = the content's length, rdi =
;       past it; CF=1 if it runs past rdx or its length is not DER
; clobbers: rax, rcx, rsi, rdi, r8
der_read:
    lea rax, [rsi + 2]
    cmp rax, rdx
    ja .bad
    movzx ecx, byte [rsi + 1]
    lea rdi, [rsi + 2]
    test cl, cl
    jns .have
    and ecx, 0x7f
    jz .bad                         ; indefinite: not DER
    cmp ecx, 3
    ja .bad
    mov r8d, ecx
    xor ecx, ecx
.len:
    cmp rdi, rdx
    jae .bad
    shl ecx, 8
    mov cl, [rdi]
    inc rdi
    dec r8d
    jnz .len
.have:
    movzx eax, byte [rsi]
    mov rsi, rdi
    add rdi, rcx
    cmp rdi, rdx
    ja .bad
    clc
    ret
.bad:
    stc
    ret

; name: der_expect
; in:   rsi = an element, rdx = end, r8b = the tag it must have
; out:  as der_read; CF=1 also if the tag differs
; clobbers: rax, rcx, rsi, rdi, r8
der_expect:
    push r8
    call der_read
    pop r8
    jc .ret
    cmp al, r8b
    je .ret                         ; CF=0
    stc
.ret:
    ret

; name: x509_parse
; in:   rdi = record, rsi = certificate, ecx = its length
; out:  the record filled; CF=1 if it is not a certificate this can read
; clobbers: caller-saved
x509_parse:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    lea rdx, [rsi + rcx]
    mov byte [rbx + X5_KEYOK], 0
    mov r8b, 0x30
    call der_expect
    jc .done
    mov rdx, rdi                    ; the certificate's end
    mov r12, rsi
    mov r8b, 0x30
    call der_expect                 ; the signed part
    jc .done
    mov [rbx + X5_TBS], r12
    mov rax, rdi
    sub rax, r12
    mov [rbx + X5_TBS_LEN], eax
    mov r13, rdi                    ; what follows it
    mov r14, rdx
    mov rdx, rdi
    cmp byte [rsi], 0xa0            ; a version
    jne .serial
    call der_read
    jc .done
    mov rsi, rdi
.serial:
    mov r8b, 0x02
    call der_expect
    jc .done
    mov rsi, rdi
    mov r8b, 0x30                   ; its signature algorithm, again
    call der_expect
    jc .done
    mov rsi, rdi
    lea r15, [rbx + X5_ISSUER]
    call x5_name
    jc .done
    mov r8b, 0x30                   ; validity
    call der_expect
    jc .done
    mov rsi, rdi
    lea r15, [rbx + X5_SUBJECT]
    call x5_name
    jc .done
    call x5_key
    jc .done
    mov rsi, r13
    mov rdx, r14
    mov r8b, 0x30                   ; the signature algorithm
    call der_expect
    jc .done
    push rdi
    mov byte [rbx + X5_ALG], X5_ECDSA_SHA256
    lea rdi, [rel x5_oid_sha256]
    call x5_oid_is
    je .alg
    mov byte [rbx + X5_ALG], X5_ECDSA_SHA384
    lea rdi, [rel x5_oid_sha384]
    call x5_oid_is
    je .alg
    mov byte [rbx + X5_ALG], 0
.alg:
    pop rsi
    mov r8b, 0x03                   ; the signature, a bit string
    call der_expect
    jc .done
    cmp byte [rbx + X5_ALG], 0
    je .done                        ; CF=0: no ECDSA signature to read
    lea rdx, [rsi + rcx]
    inc rsi                         ; no unused bits
    mov r8b, 0x30
    call der_expect
    jc .done
    mov rdx, rdi
    lea rdi, [rbx + X5_SIG]
    call x5_int
    jc .done
    lea rdi, [rbx + X5_SIG + 32]
    call x5_int
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: x5_name
; in:   rsi = a Name element, rdx = end, r15 = its pointer and length slot
; out:  them recorded; rsi past it; CF=1 if it is not a sequence
; clobbers: rax, rcx, rdi, r8
x5_name:
    mov [r15], rsi
    mov r8b, 0x30
    call der_expect
    jc .ret
    mov rsi, rdi
    sub rdi, [r15]
    mov [r15 + 8], edi
    clc
.ret:
    ret

; name: x5_key
; in:   rbx = record, rsi = the subject public key info, rdx = end
; out:  a P-256 key copied in and X5_KEYOK set; rsi past it; CF=1 if it
;       is not a key element at all
; clobbers: rax, rcx, rdi, r8, r9, r10
x5_key:
    mov r8b, 0x30
    call der_expect
    jc .ret
    push rdi
    push rdx
    lea rdx, [rsi + rcx]
    mov r8b, 0x30                   ; the algorithm and its curve
    call der_expect
    jc .out
    mov r9, rdi
    mov r10, rdx
    lea rdx, [rsi + rcx]
    lea rdi, [rel x5_oid_ec]
    call x5_oid_is
    jne .other
    mov r8b, 0x06
    call der_expect
    jc .out
    mov rsi, rdi
    lea rdi, [rel x5_oid_p256]
    call x5_oid_is
    jne .other
    mov rsi, r9
    mov rdx, r10
    mov r8b, 0x03
    call der_expect
    jc .out
    cmp ecx, 66
    jne .other
    cmp word [rsi], 0x0400          ; no unused bits, uncompressed
    jne .other
    lea rdi, [rbx + X5_KEY]
    add rsi, 2
    mov ecx, 64
    rep movsb
    mov byte [rbx + X5_KEYOK], 1
.other:
    clc
.out:
    pop rdx
    pop rsi
.ret:
    ret

; name: x5_oid_is
; in:   rsi = an element, rdi = an OID element: its length byte, then it
; out:  ZF=1 if they are the same
; clobbers: rcx, rdi
x5_oid_is:
    push rsi
    movzx ecx, byte [rdi]
    inc rdi
    repe cmpsb
    pop rsi
    ret

; name: x5_int
; in:   rsi = an INTEGER element, rdx = end, rdi = 32-byte output
; out:  it written big-endian in 32 bytes; rsi past it; CF=1 if it is
;       not an integer or does not fit
; clobbers: rax, rcx, rdi, r8, r9
x5_int:
    mov r9, rdi
    mov r8b, 0x02
    call der_expect
    jc .ret
    push rdi
.strip:
    test ecx, ecx
    jz .fit
    cmp byte [rsi], 0
    jne .fit
    inc rsi
    dec ecx
    jmp .strip
.fit:
    cmp ecx, 32
    ja .big
    mov rdi, r9
    mov eax, 32
    sub eax, ecx
    push rcx
    mov ecx, eax
    xor eax, eax
    rep stosb
    pop rcx
    rep movsb
    pop rsi
    clc
    ret
.big:
    pop rsi
    stc
.ret:
    ret

x5_oid_ec     db 9, 0x06, 7, 0x2a, 0x86, 0x48, 0xce, 0x3d, 2, 1
x5_oid_p256   db 10, 0x06, 8, 0x2a, 0x86, 0x48, 0xce, 0x3d, 3, 1, 7
x5_oid_sha256 db 10, 0x06, 8, 0x2a, 0x86, 0x48, 0xce, 0x3d, 4, 3, 2
x5_oid_sha384 db 10, 0x06, 8, 0x2a, 0x86, 0x48, 0xce, 0x3d, 4, 3, 3
