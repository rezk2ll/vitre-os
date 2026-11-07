; TLS 1.3 client (RFC 8446) over the one TCP connection, offering only
; TLS_CHACHA20_POLY1305_SHA256 and X25519. Records are read in place from
; tcp_rx at tls_pos.

TLS_WAIT_MS   equ 5000
TLS_HS_MAX    equ 65536
TLS_OUT_MAX   equ 4096
TLS_HANDSHAKE equ 22
TLS_CCS       equ 20
TLS_APP       equ 23
TLS_KEY       equ 0                 ; a key block: key, iv, record number
TLS_IV        equ 32
TLS_SEQ       equ 48
TLS_BLOCK     equ 56

; name: tls_handshake
; in:   rdi = server name, connected over TCP; interrupts on
; out:  CF=1 if the server did not answer with TLS 1.3, ChaCha20 and X25519
; clobbers: caller-saved
tls_handshake:
    sub rsp, 8
    xor eax, eax
    mov [rel tls_pos], eax
    mov [rel tls_hs_len], eax
    mov [rel tls_hs_pos], eax
    mov [rel tls_rd_on], al
    push rdi
    lea rdi, [rel tls_ctx]
    call sha256_init
    pop rdi
    call tls_hello
    jc .done
    call tls_next_msg
    jc .done
    cmp al, 2                       ; ServerHello
    jne .fail
    call tls_server_hello
    jc .done
    lea rax, [rel tls_hs_order]
    mov [rsp], rax
.msg:
    call tls_next_msg
    jc .done
    mov rdx, [rsp]
    cmp al, [rdx]
    jne .fail
    inc qword [rsp]
    cmp al, 20                      ; Finished
    je .finished
    call tls_hs_add
    jmp .msg
.finished:
    call tls_finished
    jmp .done
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    ret

; name: tls_finished
; in:   rsi = the server's Finished message, ecx = its length
; out:  it checked, the client's Finished sent, and both directions on
;       the application keys; CF=1 if it is wrong or the send failed
; clobbers: caller-saved
tls_finished:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rsi
    mov r12d, ecx
    cmp r12d, 4 + 32
    jne .fail
    call tls_transcript
    lea rdi, [rel tls_s_hs]
    lea r8, [rel tls_tmp]
    call tls_verify_data
    lea rsi, [rel tls_tmp]
    lea rdi, [rbx + 4]
    mov ecx, 32
    repe cmpsb
    jne .fail
    mov rsi, rbx
    mov ecx, r12d
    call tls_hs_add
    lea rdx, [rel tls_zero]         ; the master secret; it needs no transcript
    call tls_advance
    call tls_transcript
    lea rdi, [rel tls_secret]
    lea rsi, [rel tls_l_cap]
    lea r8, [rel tls_c_ap]
    call tls_derive
    lea rdi, [rel tls_secret]
    lea rsi, [rel tls_l_sap]
    lea r8, [rel tls_s_ap]
    call tls_derive
    mov dword [rel tls_buf], 0x20000014     ; Finished, 32 bytes
    lea rdi, [rel tls_c_hs]
    lea r8, [rel tls_buf + 4]
    call tls_verify_data
    lea rdi, [rel tls_wr]
    lea rsi, [rel tls_c_hs]
    call tls_keys
    lea rsi, [rel tls_buf]
    mov ecx, 4 + 32
    mov dl, TLS_HANDSHAKE
    call tls_send
    jc .done
    lea rdi, [rel tls_rd]
    lea rsi, [rel tls_s_ap]
    call tls_keys
    lea rdi, [rel tls_wr]
    lea rsi, [rel tls_c_ap]
    call tls_keys
    clc
    jmp .done
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; name: tls_verify_data
; in:   rdi = handshake traffic secret, r8 = 32-byte output, tls_hash
; out:  the Finished verify data: HMAC(its finished key, tls_hash)
; clobbers: caller-saved
tls_verify_data:
    push r8
    lea rsi, [rel tls_l_finished]
    xor ecx, ecx
    lea r8, [rel tls_tmp2]
    mov r9d, 32
    call tls_expand_label
    pop r8
    lea rdi, [rel tls_tmp2]
    mov esi, 32
    lea rdx, [rel tls_hash]
    mov ecx, 32
    jmp hmac_sha256

; name: tls_send
; in:   rsi = content, ecx = its length (at most TLS_OUT_MAX), dl = its type
; out:  it sent as one record sealed with tls_wr; CF=1 if the send failed
; clobbers: caller-saved
tls_send:
    push r12
    push r13
    sub rsp, 8
    movzx r13d, dl
    lea rdi, [rel tls_out + 5]
    lea r12d, [rcx + 1]             ; the content and its type
    rep movsb
    mov [rdi], r13b
    lea rdi, [rel tls_out]
    mov dword [rdi], TLS_APP | 0x0303 << 8
    lea eax, [r12 + 16]
    xchg al, ah
    mov [rdi + 3], ax
    lea rdi, [rel tls_wr]
    call tls_nonce
    lea rdi, [rel tls_wr + TLS_KEY]
    lea rsi, [rel tls_nonce_buf]
    lea rdx, [rel tls_out]
    mov ecx, 5
    lea r8, [rel tls_out + 5]
    mov r9d, r12d
    call aead_seal
    lea rsi, [rel tls_out]
    lea ecx, [r12 + 5 + 16]
    call tcp_write
    lea rsp, [rsp + 8]
    pop r13
    pop r12
    ret

; name: tls_server_hello
; in:   rsi = the ServerHello message, ecx = its length
; out:  it hashed, the shared secret and handshake keys made, reading
;       switched to them; CF=1 if it does not pick TLS 1.3, ChaCha20 and
;       an X25519 key (a HelloRetryRequest included)
; clobbers: caller-saved
tls_server_hello:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rsi
    mov r12d, ecx
    call tls_hs_add
    cmp r12d, 44
    jb .fail
    cmp byte [rbx + 38], 0          ; the empty session id ours echoed
    jne .fail
    lea rsi, [rbx + 39]             ; past type, length, version, random
    cmp word [rsi], 0x0313          ; 13 03
    jne .fail
    add rsi, 5
    lea rdx, [rbx + r12]
    mov byte [rel tls_got], 0
.ext:
    lea rax, [rsi + 4]
    cmp rax, rdx
    ja .check
    movzx eax, word [rsi]
    movzx ecx, word [rsi + 2]
    xchg cl, ch
    lea rdi, [rsi + rcx + 4]
    cmp rdi, rdx
    ja .fail
    cmp ax, 0x2b00                  ; supported_versions
    jne .key_share
    cmp ecx, 2
    jne .fail
    cmp word [rsi + 4], 0x0403
    jne .fail
    or byte [rel tls_got], 1
.key_share:
    cmp ax, 0x3300
    jne .next
    cmp ecx, 36                     ; not a HelloRetryRequest's bare group
    jne .fail
    cmp dword [rsi + 4], 0x20001d00 ; x25519, 32 bytes
    jne .fail
    push rsi
    push rcx
    lea rdi, [rel tls_peer]
    add rsi, 8
    mov ecx, 32
    rep movsb
    pop rcx
    pop rsi
    or byte [rel tls_got], 2
.next:
    lea rsi, [rsi + rcx + 4]
    jmp .ext
.check:
    cmp byte [rel tls_got], 3
    jne .fail
    lea rdi, [rel tls_shared]
    lea rsi, [rel tls_priv]
    lea rdx, [rel tls_peer]
    call x25519
    lea rdi, [rel tls_zero]         ; the early secret, without a PSK
    mov esi, 32
    lea rdx, [rel tls_zero]
    mov ecx, 32
    lea r8, [rel tls_secret]
    call hmac_sha256
    lea rdx, [rel tls_shared]
    call tls_advance
    call tls_transcript
    lea rdi, [rel tls_secret]
    lea rsi, [rel tls_l_chs]
    lea r8, [rel tls_c_hs]
    call tls_derive
    lea rdi, [rel tls_secret]
    lea rsi, [rel tls_l_shs]
    lea r8, [rel tls_s_hs]
    call tls_derive
    lea rdi, [rel tls_rd]
    lea rsi, [rel tls_s_hs]
    call tls_keys
    mov byte [rel tls_rd_on], 1
    clc
    jmp .done
.fail:
    stc
.done:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; name: tls_advance
; in:   rdx = 32-byte input key material, tls_secret
; out:  tls_secret = HKDF-Extract(Derive-Secret(tls_secret, "derived", ""),
;       the input), the next secret of the key schedule
; clobbers: caller-saved
tls_advance:
    push rdx
    call tls_empty_hash
    lea rdi, [rel tls_secret]
    lea rsi, [rel tls_l_derived]
    lea r8, [rel tls_tmp]
    call tls_derive
    pop rdx
    lea rdi, [rel tls_tmp]
    mov esi, 32
    mov ecx, 32
    lea r8, [rel tls_secret]
    jmp hmac_sha256

; name: tls_keys
; in:   rdi = key block, rsi = traffic secret
; out:  the block's key and iv derived, its record number 0
; clobbers: caller-saved
tls_keys:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rel tls_l_key]
    xor ecx, ecx
    lea r8, [rbx + TLS_KEY]
    mov r9d, 32
    call tls_expand_label
    mov rdi, r12
    lea rsi, [rel tls_l_iv]
    xor ecx, ecx
    lea r8, [rbx + TLS_IV]
    mov r9d, 12
    call tls_expand_label
    mov qword [rbx + TLS_SEQ], 0
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: tls_transcript
; in:   tls_ctx
; out:  tls_hash = the hash of the handshake so far; tls_ctx goes on
; clobbers: caller-saved
tls_transcript:
    lea rdi, [rel tls_tmpctx]
    lea rsi, [rel tls_ctx]
    mov ecx, SHA_CTX_SIZE
    rep movsb
    jmp tls_hash_tmp

; name: tls_empty_hash
; in:   none
; out:  tls_hash = the hash of nothing
; clobbers: caller-saved
tls_empty_hash:
    lea rdi, [rel tls_tmpctx]
    call sha256_init
tls_hash_tmp:
    lea rdi, [rel tls_tmpctx]
    lea rsi, [rel tls_hash]
    jmp sha256_final

; name: tls_next_msg
; in:   interrupts on
; out:  rsi = the next handshake message, ecx = its length with the
;       header, al = its type; CF=1 if the records ran out or were bad
; clobbers: caller-saved
tls_next_msg:
    mov eax, [rel tls_hs_len]
    sub eax, [rel tls_hs_pos]
    cmp eax, 4
    jb .more
    lea rsi, [rel tls_hs]
    mov edx, [rel tls_hs_pos]
    add rsi, rdx
    movzx ecx, byte [rsi + 1]
    shl ecx, 16
    movzx edx, word [rsi + 2]
    xchg dl, dh
    or ecx, edx
    add ecx, 4
    cmp eax, ecx
    jb .more
    add [rel tls_hs_pos], ecx
    movzx eax, byte [rsi]
    clc
    ret
.more:
    call tls_read_record
    jnc tls_next_msg
    ret

; name: tls_read_record
; in:   interrupts on
; out:  the next handshake record's content appended to tls_hs, change
;       cipher spec records skipped; CF=1 on anything else, a record that
;       does not decrypt, or a timeout
; clobbers: caller-saved
tls_read_record:
    mov esi, [rel tls_hs_pos]       ; move what is left to the front
    mov ecx, [rel tls_hs_len]
    sub ecx, esi
    mov [rel tls_hs_len], ecx
    mov dword [rel tls_hs_pos], 0
    lea rdi, [rel tls_hs]
    add rsi, rdi
    rep movsb
.read:
    call tls_record
    jc .ret
    cmp al, TLS_CCS
    je .read
    cmp byte [rel tls_rd_on], 0
    je .plain
    cmp al, TLS_APP
    jne .fail
    call tls_decrypt
    jc .ret
.plain:
    cmp al, TLS_HANDSHAKE
    jne .fail
    mov edx, [rel tls_hs_len]
    lea eax, [rdx + rcx]
    cmp eax, TLS_HS_MAX
    ja .fail
    mov [rel tls_hs_len], eax
    lea rdi, [rel tls_hs]
    add rdi, rdx
    rep movsb
    clc
.ret:
    ret
.fail:
    stc
    ret

; name: tls_decrypt
; in:   rdx = record, rsi = payload, ecx = its length
; out:  rsi = the content, ecx = its length, al = the inner type; CF=1 if
;       it does not authenticate
; clobbers: caller-saved
tls_decrypt:
    push rbx
    push r12
    push r13
    mov rbx, rdx
    mov r12, rsi
    mov r13d, ecx
    sub r13d, 16
    jb .done
    lea rdi, [rel tls_rd]
    call tls_nonce
    lea rdi, [rel tls_rd + TLS_KEY]
    lea rsi, [rel tls_nonce_buf]
    mov rdx, rbx
    mov ecx, 5
    mov r8, r12
    mov r9d, r13d
    call aead_open
    jc .done
.strip:                             ; the type is the last byte not 0
    test r13d, r13d
    jz .bad
    dec r13d
    movzx eax, byte [r12 + r13]
    test al, al
    jz .strip
    mov rsi, r12
    mov ecx, r13d
    clc
    jmp .done
.bad:
    stc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: tls_nonce
; in:   rdi = key block
; out:  tls_nonce_buf = its iv xor its record number; the number advanced
; clobbers: rax
tls_nonce:
    mov rax, [rdi + TLS_IV]
    mov [rel tls_nonce_buf], rax
    mov eax, [rdi + TLS_IV + 8]
    mov [rel tls_nonce_buf + 8], eax
    mov rax, [rdi + TLS_SEQ]
    inc qword [rdi + TLS_SEQ]
    bswap rax
    xor [rel tls_nonce_buf + 4], rax
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

; name: tls_derive
; in:   rdi = secret, rsi = label, r8 = 32-byte output, tls_hash
; out:  Derive-Secret(secret, label, the messages hashed in tls_hash)
; clobbers: caller-saved
tls_derive:
    lea rdx, [rel tls_hash]
    mov ecx, 32
    mov r9d, 32
    ; fall through

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
tls_l_derived  db "derived", 0
tls_l_chs      db "c hs traffic", 0
tls_l_shs      db "s hs traffic", 0
tls_l_key      db "key", 0
tls_l_iv       db "iv", 0
tls_l_finished db "finished", 0
tls_l_cap      db "c ap traffic", 0
tls_l_sap      db "s ap traffic", 0
tls_hs_order   db 8, 11, 15, 20     ; extensions, certificate, its proof, Finished
tls_msg_ok     db "[tls] handshake done; the certificate is NOT verified", 10, 0
tls_msg_failed db "[tls] handshake failed", 10, 0
tls_msg_usage  db "usage: tls <host> <port>", 10, 0

section .bss
alignb 8
tls_pos       resd 1
tls_hs_len    resd 1
tls_hs_pos    resd 1
tls_rd_on     resb 1
tls_got       resb 1
alignb 8
tls_rd        resb TLS_BLOCK
tls_wr        resb TLS_BLOCK
tls_nonce_buf resb 12
tls_ctx       resb SHA_CTX_SIZE
tls_tmpctx    resb SHA_CTX_SIZE
tls_rng       resb SHA_CTX_SIZE
tls_pool      resb 32               ; with tls_seed right after it
tls_seed      resq 2
tls_zero      resb 32
tls_priv      resb 32
tls_pub       resb 32
tls_peer      resb 32
tls_shared    resb 32
tls_secret    resb 32
tls_c_hs      resb 32
tls_s_hs      resb 32
tls_c_ap      resb 32
tls_s_ap      resb 32
tls_hash      resb 32
tls_tmp       resb 32
tls_tmp2      resb 32
tls_label     resb 2 + 1 + 6 + 32 + 1 + 32
tls_buf       resb 512
tls_hs        resb TLS_HS_MAX
tls_out       resb 5 + TLS_OUT_MAX + 1 + 16
section .text
