; X.509 certificates (RFC 5280), DER read in place: only the parts a chain
; check needs. A parsed certificate is a record of X5_SIZE bytes.

X5_TBS      equ 0                   ; the signed part, as a whole element
X5_TBS_LEN  equ 8
X5_ISSUER   equ 16                  ; issuer and subject names, likewise
X5_ISS_LEN  equ 24
X5_SUBJECT  equ 32
X5_SUB_LEN  equ 40
X5_SAN      equ 48                  ; the subject alternative names' content
X5_SAN_LEN  equ 56
X5_ALG     equ 60                  ; X5_ECDSA_SHA256, X5_ECDSA_SHA384 or 0
X5_KEYOK    equ 61                  ; 1 if the key is a P-256 one
X5_CA       equ 62                  ; 1 if it may sign certificates
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
    mov byte [rbx + X5_CA], 0
    mov qword [rbx + X5_SAN], 0
    mov dword [rbx + X5_SAN_LEN], 0
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
.ext:
    cmp rsi, rdx
    jae .tail
    call der_read
    jc .done
    cmp al, 0xa3
    jne .next
    push rdi
    push rdx
    call x5_extensions
    pop rdx
    pop rdi
    jc .done
.next:
    mov rsi, rdi
    jmp .ext
.tail:
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

; name: x5_extensions
; in:   rbx = record, rsi = the [3] content, ecx = its length
; out:  the subject alternative names and the CA flag recorded if they
;       are there; CF=1 if the extensions are malformed
; clobbers: rax, rcx, rdx, rsi, rdi, r8, r9
x5_extensions:
    lea rdx, [rsi + rcx]
    mov r8b, 0x30
    call der_expect
    jc .ret
    lea rdx, [rsi + rcx]
.each:
    cmp rsi, rdx
    jae .ret                        ; CF=0 from the compare
    mov r8b, 0x30
    call der_expect
    jc .ret
    push rdi
    push rdx
    lea rdx, [rsi + rcx]
    lea rdi, [rel x5_oid_san]
    call x5_oid_is
    mov r9d, 0
    je .known
    lea rdi, [rel x5_oid_bc]
    call x5_oid_is
    jne .other
    mov r9d, 1
.known:
    mov r8b, 0x06
    call der_expect
    jc .skip
    mov rsi, rdi
    cmp byte [rsi], 0x01            ; critical or not
    jne .value
    call der_read
    jc .skip
    mov rsi, rdi
.value:
    mov r8b, 0x04
    call der_expect
    jc .skip
    lea rdx, [rsi + rcx]
    mov r8b, 0x30
    call der_expect
    jc .skip
    test r9d, r9d
    jnz .bc
    mov [rbx + X5_SAN], rsi
    mov [rbx + X5_SAN_LEN], ecx
    jmp .other
.bc:
    cmp ecx, 3
    jb .other                       ; cA left out: FALSE
    cmp word [rsi], 0x0101          ; BOOLEAN, 1 byte
    jne .other
    cmp byte [rsi + 2], 0
    setne [rbx + X5_CA]
.other:
    clc
.skip:
    pop rdx
    pop rsi
    jc .ret
    jmp .each
.ret:
    ret

; name: x509_signed_by
; in:   rdi = a parsed certificate, rsi = the CA certificate said to issue it
; out:  CF=0 if the CA's subject is its issuer and the CA's key signed it
; clobbers: caller-saved
x509_signed_by:
    cmp byte [rsi + X5_CA], 0
    je .fail
    cmp byte [rsi + X5_KEYOK], 0
    je .fail
    mov ecx, [rdi + X5_ISS_LEN]
    cmp ecx, [rsi + X5_SUB_LEN]
    jne .fail
    push rdi
    push rsi
    mov rdi, [rdi + X5_ISSUER]
    mov rsi, [rsi + X5_SUBJECT]
    repe cmpsb
    pop rsi
    pop rdi
    jne .fail
    add rsi, X5_KEY
    jmp x509_sig_by_key
.fail:
    stc
    ret

; name: x509_sig_by_key
; in:   rdi = a parsed certificate, rsi = a P-256 key, x then y
; out:  CF=0 if that key signed it with ECDSA and SHA-256
; clobbers: caller-saved
x509_sig_by_key:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    cmp byte [rbx + X5_ALG], X5_ECDSA_SHA256
    jne .fail
    lea rdi, [rel x5_ctx]
    call sha256_init
    lea rdi, [rel x5_ctx]
    mov rsi, [rbx + X5_TBS]
    mov edx, [rbx + X5_TBS_LEN]
    call sha256_update
    lea rdi, [rel x5_ctx]
    lea rsi, [rel x5_hash]
    call sha256_final
    mov rdi, r12
    lea rsi, [rel x5_hash]
    lea rdx, [rbx + X5_SIG]
    call ecdsa_verify
    jmp .done
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; name: x509_host_ok
; in:   rdi = record, rsi = host name or dotted address, zero-terminated
; out:  CF=0 if a subject alternative name matches it: a DNS name, any
;       case, "*." standing for one whole leftmost label, or an IP address
; clobbers: caller-saved
x509_host_ok:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    xor ecx, ecx
.len:
    cmp byte [rdi + rcx], 0
    je .have_len
    inc ecx
    jmp .len
.have_len:
    mov r13d, ecx
    mov rdi, r12
    call net_parse_ip
    mov [rsp], eax
    setnc [rsp + 4]
    mov rsi, [rbx + X5_SAN]
    test rsi, rsi
    jz .fail
    mov edx, [rbx + X5_SAN_LEN]
    add rdx, rsi
.each:
    cmp rsi, rdx
    jae .fail
    call der_read
    jc .fail
    mov r14, rdi
    cmp al, 0x87                    ; iPAddress
    je .ip
    cmp al, 0x82                    ; dNSName
    jne .next
    cmp byte [rsp + 4], 0           ; an address only matches an address
    jne .next
    call x5_dns_match
    je .ok
    jmp .next
.ip:
    cmp ecx, 4
    jne .next
    cmp byte [rsp + 4], 0
    je .next
    mov eax, [rsi]
    cmp eax, [rsp]
    je .ok
.next:
    mov rsi, r14
    jmp .each
.ok:
    clc
    jmp .done
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: x5_dns_match
; in:   rsi = a DNS name from the certificate, ecx = its length, r12 =
;       host, r13d = its length
; out:  ZF=1 if they match
; clobbers: rax, rcx, rsi, rdi
x5_dns_match:
    mov rdi, r12
    cmp ecx, 2
    jb .exact
    cmp word [rsi], 0x2e2a          ; "*."
    jne .exact
    inc rsi                         ; match ".rest" against the host after
    dec ecx                         ; its first label
    mov eax, 1
.dots:                              ; "*.com" would cover a whole TLD
    cmp eax, ecx
    jae .no
    cmp byte [rsi + rax], '.'
    je .wild
    inc eax
    jmp .dots
.wild:
    mov eax, r13d
.find:
    test eax, eax
    jz .no
    cmp byte [rdi], '.'
    je .found
    inc rdi
    dec eax
    jmp .find
.found:
    cmp rdi, r12
    je .no                          ; an empty first label
    cmp eax, ecx
    jne .no
    jmp x5_ieq
.exact:
    test ecx, ecx
    jz .no
    cmp ecx, r13d
    jne .no
    jmp x5_ieq
.no:
    test rsp, rsp                   ; ZF=0
    ret

; name: x5_ieq
; in:   rsi, rdi = strings, ecx = length
; out:  ZF=1 if they are equal, ASCII letters in any case
; clobbers: rax, rcx, rsi, rdi
x5_ieq:
    test ecx, ecx
    jz .ret
    mov al, [rsi]
    mov ah, [rdi]
    cmp al, 'A'
    jb .a
    cmp al, 'Z'
    ja .a
    or al, 0x20
.a:
    cmp ah, 'A'
    jb .b
    cmp ah, 'Z'
    ja .b
    or ah, 0x20
.b:
    cmp al, ah
    jne .ret
    inc rsi
    inc rdi
    dec ecx
    jmp x5_ieq
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
x5_oid_san    db 5, 0x06, 3, 0x55, 0x1d, 0x11
x5_oid_bc     db 5, 0x06, 3, 0x55, 0x1d, 0x13

section .bss
alignb 8
x5_ctx        resb SHA_CTX_SIZE
x5_hash       resb 32
section .text
