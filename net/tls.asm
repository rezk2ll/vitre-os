; TLS 1.3 client (RFC 8446) over the one TCP connection, offering only
; TLS_CHACHA20_POLY1305_SHA256 and X25519. Records are read in place from
; tcp_rx at tls_pos.

TLS_WAIT_MS   equ 5000
TLS_HANDSHAKE equ 22

; name: tls_handshake
; in:   rdi = server name, connected over TCP; interrupts on
; out:  CF=1 if the server did not answer with a ServerHello
; clobbers: caller-saved
tls_handshake:
    sub rsp, 8
    mov dword [rel tls_pos], 0
    push rdi
    lea rdi, [rel tls_ctx]
    call sha256_init
    pop rdi
    call tls_hello
    jc .done
    call tls_record
    jc .done
    cmp al, TLS_HANDSHAKE
    jne .fail
    test ecx, ecx
    jz .fail
    cmp byte [rsi], 2               ; ServerHello
    je .done                        ; CF=0
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    ret

; name: tls_hello
; in:   rdi = server name
; out:  a fresh key pair; the ClientHello sent and hashed; CF=1 if the
;       send failed
; clobbers: caller-saved
tls_hello:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    xor ecx, ecx
.name_len:
    cmp byte [rbx + rcx], 0
    je .keys
    inc ecx
    cmp ecx, 255                    ; the most a host name can be
    jbe .name_len
    stc
    jmp .done
.keys:
    mov [rsp], ecx
    lea rdi, [rel tls_priv]
    call tls_random
    lea rdi, [rel tls_pub]
    lea rsi, [rel tls_priv]
    lea rdx, [rel tls_base]
    call x25519
    lea rdi, [rel tls_buf]
    lea rsi, [rel tls_ch_head]
    mov ecx, tls_ch_mid - tls_ch_head
    rep movsb
    call tls_random
    lea rsi, [rel tls_ch_mid]
    mov ecx, tls_ch_ext - tls_ch_mid
    rep movsb
    mov r12, rdi                    ; the extensions' length goes here
    add rdi, 2
    mov rsi, rbx
    mov ecx, [rsp]                  ; the name's length
    xor eax, eax                    ; server_name: one host name
    stosw
    lea eax, [rcx + 5]
    call tls_put16
    lea eax, [rcx + 3]
    call tls_put16
    xor eax, eax
    stosb
    mov eax, ecx
    call tls_put16
    rep movsb
    lea rsi, [rel tls_ch_ext]
    mov ecx, tls_ch_end - tls_ch_ext
    rep movsb
    lea rsi, [rel tls_pub]
    mov ecx, 32
    rep movsb
    mov rax, rdi
    sub rax, r12
    sub eax, 2
    xchg al, ah
    mov [r12], ax
    lea rsi, [rel tls_buf]
    sub rdi, rsi
    mov r12d, edi                   ; the whole record
    lea eax, [rdi - 5]
    xchg al, ah
    mov [rsi + 3], ax
    lea eax, [rdi - 9]
    xchg al, ah
    mov [rsi + 7], ax
    add rsi, 5
    lea ecx, [r12 - 5]
    call tls_hs_add
    lea rsi, [rel tls_buf]
    mov ecx, r12d
    call tcp_write
.done:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; name: tls_hs_add
; in:   rsi = handshake message, ecx = its length
; out:  it added to the transcript
; clobbers: caller-saved
tls_hs_add:
    lea rdi, [rel tls_ctx]
    mov edx, ecx
    jmp sha256_update

; name: tls_record
; in:   interrupts on
; out:  rdx = the next record, rsi = its payload, ecx = the payload's
;       length, al = its type; tls_pos past it; CF=1 on a timeout or close
; clobbers: caller-saved
tls_record:
    mov ecx, 5
    call tls_wait
    jc .ret
    lea rdx, [rel tcp_rx]
    mov eax, [rel tls_pos]
    movzx ecx, word [rdx + rax + 3]
    xchg cl, ch
    add ecx, 5
    push rcx
    call tls_wait
    pop rcx
    jc .ret
    lea rdx, [rel tcp_rx]
    mov eax, [rel tls_pos]
    add rdx, rax
    add [rel tls_pos], ecx
    sub ecx, 5
    lea rsi, [rdx + 5]
    movzx eax, byte [rdx]
    clc
.ret:
    ret

; name: tls_wait
; in:   ecx = bytes wanted past tls_pos; interrupts on
; out:  CF=1 if they did not arrive within TLS_WAIT_MS or the peer closed
; clobbers: caller-saved
tls_wait:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, ecx
    mov r12, [rel timer_ticks]
.check:
    mov eax, [rel tcp_rx_len]
    sub eax, [rel tls_pos]
    cmp eax, ebx
    jae .done                       ; CF=0
    cmp byte [rel tcp_peer_closed], 0
    jne .fail
    mov rax, [rel timer_ticks]
    sub rax, r12
    cmp rax, TLS_WAIT_MS
    jae .fail
    call task_yield
    jmp .check
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; name: tls_random
; in:   rdi = 32-byte output
; out:  it filled from the TSC and tick count stirred into a pool; rdi
;       past it. Not a strong generator: see D26
; clobbers: caller-saved except rdi
tls_random:
    push rbx
    mov rbx, rdi
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov [rel tls_seed], rax
    mov rax, [rel timer_ticks]
    mov [rel tls_seed + 8], rax
    lea rdi, [rel tls_rng]
    call sha256_init
    lea rdi, [rel tls_rng]
    lea rsi, [rel tls_pool]         ; the pool, then the seed
    mov edx, 48
    call sha256_update
    lea rdi, [rel tls_tmpctx]       ; the output and the next pool hash
    lea rsi, [rel tls_rng]          ; apart, so one does not give the other
    mov ecx, SHA_CTX_SIZE
    rep movsb
    lea rdi, [rel tls_rng]
    mov rsi, rbx
    call sha256_final
    lea rdi, [rel tls_tmpctx]
    lea rsi, [rel tls_one]
    mov edx, 1
    call sha256_update
    lea rdi, [rel tls_tmpctx]
    lea rsi, [rel tls_pool]
    call sha256_final
    lea rdi, [rbx + 32]
    pop rbx
    ret

; name: cmd_tls
; in:   rdi = "host port"
; out:  a TLS handshake tried, and how far it got
; clobbers: caller-saved
cmd_tls:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    cmp byte [rel net_ready], 0
    je .no_net
.find:
    mov al, [rdi]
    test al, al
    jz .usage
    inc rdi
    cmp al, ' '
    jne .find
    mov byte [rdi - 1], 0
    call parse_dec
    jc .usage
    mov r12d, eax
    mov rdi, rbx
    call net_resolve
    jc .failed
    mov edi, eax
    mov esi, r12d
    call tcp_connect
    jc .failed
    mov rdi, rbx
    call tls_handshake
    pushf
    call tcp_close
    popf
    jc .failed
    lea rdi, [rel tls_msg_ok]
    jmp .print
.failed:
    lea rdi, [rel tls_msg_failed]
    jmp .print
.usage:
    lea rdi, [rel tls_msg_usage]
    jmp .print
.no_net:
    lea rdi, [rel net_msg_none]
.print:
    call kputs
    add rsp, 8
    pop r12
    pop rbx
    ret

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

tls_ch_head db TLS_HANDSHAKE, 3, 1, 0, 0, 1, 0, 0, 0, 3, 3
tls_ch_mid  db 0, 0, 2, 0x13, 0x03, 1, 0    ; no session id, one suite
tls_ch_ext  db 0, 0x0a, 0, 4, 0, 2, 0, 0x1d                 ; groups: x25519
            db 0, 0x0d, 0, 14, 0, 12, 4, 3, 8, 4, 4, 1, 5, 3, 8, 5, 5, 1
            db 0, 0x2b, 0, 3, 2, 3, 4                       ; TLS 1.3
            db 0, 0x33, 0, 38, 0, 36, 0, 0x1d, 0, 32        ; then the key
tls_ch_end:
tls_base       db 9
               times 31 db 0
tls_one        db 1
tls_prefix     db "tls13 "
tls_msg_ok     db "[tls] server hello received", 10, 0
tls_msg_failed db "[tls] handshake failed", 10, 0
tls_msg_usage  db "usage: tls <host> <port>", 10, 0

section .bss
alignb 8
tls_pos    resd 1
alignb 8
tls_ctx    resb SHA_CTX_SIZE
tls_tmpctx resb SHA_CTX_SIZE
tls_rng    resb SHA_CTX_SIZE
tls_pool   resb 32                  ; with tls_seed right after it
tls_seed   resq 2
tls_priv   resb 32
tls_pub    resb 32
tls_label  resb 2 + 1 + 6 + 32 + 1 + 32
tls_buf    resb 512
section .text
