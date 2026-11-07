; HTTP/1.0 GET: one request per connection, the response read until the
; server closes it.

HTTP_PORT     equ 80
HTTPS_PORT    equ 443
HTTP_REQ_MAX  equ 512
HTTP_IDLE_MS  equ 10000

; name: http_get
; in:   rdi = "http://host:port/path", with the scheme, port and path
;       optional; interrupts on
; out:  the whole response in tcp_rx, tcp_rx_len bytes, or only the bytes
;       http_range_from to http_range_to when http_range_to is set (it is
;       cleared); CF=1 if the host
;       has no address, refused, the send failed, or the URL is too long
; clobbers: caller-saved
http_get:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov byte [rel tls_verified], 0  ; a fetch that fails early shows no stale result
    mov byte [rel http_tls], 1
    mov dword [rel http_port], HTTPS_PORT
    lea rsi, [rel http_scheme_tls]
    mov ecx, 8
    repe cmpsb
    je .tls
    mov byte [rel http_tls], 0
    mov dword [rel http_port], HTTP_PORT
    mov rdi, rbx
    lea rsi, [rel http_scheme]
    mov ecx, 7
    repe cmpsb
    jne .host
    add rbx, 7
    jmp .host
.tls:
    add rbx, 8
.host:
    lea rdi, [rel http_host]
    mov rsi, rbx
    lea rdx, [rdi + HTTP_HOST_MAX - 1]
.host_char:
    mov al, [rsi]
    test al, al
    jz .host_end
    cmp al, '/'
    je .host_end
    cmp al, ':'
    je .host_end
    cmp rdi, rdx
    jae .fail
    stosb
    inc rsi
    jmp .host_char
.host_end:
    mov byte [rdi], 0
    cmp byte [rsi], ':'
    jne .port_end
    xor eax, eax
.port:
    inc rsi
    movzx ecx, byte [rsi]
    sub ecx, '0'
    cmp ecx, 9
    ja .port_set
    imul eax, eax, 10
    add eax, ecx
    cmp eax, 0xffff
    ja .fail
    jmp .port
.port_set:
    test eax, eax
    jz .fail
    mov [rel http_port], eax
.port_end:
    mov r12, rsi                    ; the path, or an empty string
    lea rdi, [rel http_request]
    lea rdx, [rdi + HTTP_REQ_MAX]
    lea rsi, [rel http_get_line]
    clc
    call http_append
    mov rsi, r12
    cmp byte [rsi], 0
    jne .path
    lea rsi, [rel http_root]
.path:
    call http_append
    lea rsi, [rel http_host_line]
    call http_append
    lea rsi, [rel http_host]
    call http_append
    jc .fail
    cmp qword [rel http_range_to], 0
    je .tail
    call http_append_range
.tail:
    lea rsi, [rel http_tail]
    call http_append
    jc .fail
    lea rax, [rel http_request]
    sub rdi, rax
    mov r13d, edi                   ; request length
    lea rdi, [rel http_host]
    call net_resolve
    jc .fail
    mov edi, eax
    mov esi, [rel http_port]
    call tcp_connect
    jc .fail
    cmp byte [rel http_tls], 0
    jne .tls_get
    lea rsi, [rel http_request]
    mov ecx, r13d
    call tcp_write
    jc .unsent
    mov r12, [rel timer_ticks]      ; read until closed or idle too long
    mov r13d, [rel tcp_rx_len]
.read:
    cmp byte [rel tcp_peer_closed], 0
    jne .close
    call task_yield
    mov eax, [rel tcp_rx_len]
    cmp eax, r13d
    je .idle
    mov r13d, eax
    mov r12, [rel timer_ticks]
.idle:
    mov rax, [rel timer_ticks]
    sub rax, r12
    cmp rax, HTTP_IDLE_MS
    jb .read
.close:
    call tcp_close
    clc
    jmp .done
.tls_get:
    lea rdi, [rel http_host]
    call tls_handshake
    jc .unsent
    lea rsi, [rel http_request]
    mov ecx, r13d
    mov dl, TLS_APP
    call tls_send
    jc .unsent
    call tls_read_all
    jc .unsent
    mov r13d, eax
    call tcp_close                  ; nothing lands in tcp_rx after this
    mov [rel tcp_rx_len], r13d
    clc
    jmp .done
.unsent:
    call tcp_close
.fail:
    stc
.done:
    mov qword [rel http_range_to], 0  ; the next request asks for everything
    pop r13
    pop r12
    pop rbx
    ret

; name: http_append
; in:   rdi = write position, rdx = end of the buffer, rsi = string
; out:  the string copied, rdi past it; CF=1 (and stays set across calls)
;       if it did not fit
; clobbers: rax, rsi
http_append:
    jc .done
.char:
    lodsb
    test al, al
    jz .done                        ; CF=0 from the test
    cmp rdi, rdx
    jae .full
    stosb
    jmp .char
.full:
    stc
.done:
    ret

; name: http_append_range
; in:   rdi = write position, rdx = end of the buffer; http_range_from and
;       http_range_to set
; out:  a Range header line appended, rdi past it; CF=1 if it did not fit
; clobbers: rax, rcx, rsi
http_append_range:
    push rdx
    push rdi
    lea rdi, [rel http_range_text]
    lea rsi, [rel http_range_line]
.copy:
    lodsb
    stosb
    test al, al
    jnz .copy
    dec rdi
    mov rsi, [rel http_range_from]
    call str_put_dec
    mov byte [rdi], '-'
    inc rdi
    mov rsi, [rel http_range_to]
    call str_put_dec
    pop rdi
    pop rdx
    lea rsi, [rel http_range_text]
    clc
    jmp http_append

; name: http_body
; in:   a response in tcp_rx
; out:  rax = its body, ecx = the body's length (the whole response if it
;       has no header end)
; clobbers: rax, rcx, rdx
http_body:
    lea rax, [rel tcp_rx]
    mov ecx, [rel tcp_rx_len]
    lea rdx, [rax + rcx - 3]
.find:
    cmp rax, rdx
    jae .whole
    cmp dword [rax], 0x0a0d0a0d     ; "\r\n\r\n"
    je .found
    inc rax
    jmp .find
.found:
    add rax, 4
    lea rdx, [rel tcp_rx]
    sub rdx, rax
    add ecx, edx
    ret
.whole:
    lea rax, [rel tcp_rx]
    ret

; name: http_redirect
; in:   a response in tcp_rx
; out:  CF=0 and http_location = its Location header when the status is
;       3xx; CF=1 if it is not a redirect or has no Location
; clobbers: rax, rcx, rdx, rsi, rdi
http_redirect:
    lea rsi, [rel tcp_rx]
    mov ecx, [rel tcp_rx_len]
    cmp ecx, 12
    jb .no
    cmp dword [rsi], 'HTTP'
    jne .no
    cmp byte [rsi + 9], '3'         ; "HTTP/1.x 3"
    jne .no
    lea rdx, [rsi + rcx - 9]        ; a header name fits before this
.line:
    cmp rsi, rdx
    jae .no
    lodsb
    cmp al, 10
    jne .line
    cmp byte [rsi], 13              ; the blank line ends the headers
    je .no
    lea rdi, [rel http_loc_name]
    xor ecx, ecx
.name:
    mov al, [rsi + rcx]
    or al, 0x20                     ; lower case; ':' already has the bit
    cmp al, [rdi + rcx]
    jne .line
    inc ecx
    cmp ecx, 9
    jb .name
    add rsi, 9
    add rdx, 9                      ; the response's end
.space:
    cmp rsi, rdx
    jae .no
    cmp byte [rsi], ' '
    jne .value
    inc rsi
    jmp .space
.value:
    lea rdi, [rel http_location]
    lea rcx, [rdi + HTTP_HOST_MAX - 1]
.copy:
    cmp rsi, rdx
    jae .end
    mov al, [rsi]
    cmp al, 13
    je .end
    cmp al, 10
    je .end
    cmp rdi, rcx
    jae .no                         ; too long to follow
    stosb
    inc rsi
    jmp .copy
.end:
    mov byte [rdi], 0
    lea rax, [rel http_location]
    cmp rdi, rax
    je .no
    clc
    ret
.no:
    stc
    ret

; name: cmd_get
; in:   rdi = URL
; out:  the response printed without CRs, then its size
; clobbers: caller-saved
cmd_get:
    push rbx
    push r12
    sub rsp, 8
    cmp byte [rel net_ready], 0
    je .no_net
    call http_get
    jc .failed
    lea rbx, [rel tcp_rx]
    mov r12d, [rel tcp_rx_len]
.char:
    test r12d, r12d
    jz .size
    movzx edi, byte [rbx]
    inc rbx
    dec r12d
    cmp edi, 13
    je .char
    call kputc
    jmp .char
.size:
    lea rdi, [rel http_msg_size]
    call kputs
    cmp byte [rel http_tls], 0
    je .bytes
    lea rdi, [rel http_msg_unverified]
    cmp byte [rel tls_verified], 0
    je .tls
    lea rdi, [rel http_msg_verified]
.tls:
    call kputs
.bytes:
    mov edi, [rel tcp_rx_len]
    call [rel jt_kput_dec]
    lea rdi, [rel http_msg_bytes]
    jmp .print
.failed:
    lea rdi, [rel http_msg_failed]
    jmp .print
.no_net:
    lea rdi, [rel net_msg_none]
.print:
    call kputs
    add rsp, 8
    pop r12
    pop rbx
    ret

HTTP_HOST_MAX equ 256

http_scheme     db "http://"
http_scheme_tls db "https://"
http_get_line   db "GET ", 0
http_root       db "/", 0
http_host_line  db " HTTP/1.0", 13, 10, "Host: ", 0
http_range_line db 13, 10, "Range: bytes=", 0
http_tail       db 13, 10, "User-Agent: vitre", 13, 10, "Connection: close", 13, 10, 13, 10, 0
http_msg_size   db 10, "[http] ", 0
http_msg_bytes  db " bytes", 10, 0
http_msg_unverified db "over TLS, certificate NOT verified, ", 0
http_msg_verified db "over TLS, certificate verified, ", 0
http_msg_failed db "[http] no response", 10, 0
http_loc_name   db "location:"

section .bss
alignb 8
http_range_from resq 1              ; with http_range_to, the bytes the next
http_range_to   resq 1              ; http_get asks for; 0 to 0 for all
http_range_text resb 64
http_port    resd 1
http_tls     resb 1                 ; the last URL was https: not verified
http_host    resb HTTP_HOST_MAX
http_location resb HTTP_HOST_MAX
http_request resb HTTP_REQ_MAX
section .text
