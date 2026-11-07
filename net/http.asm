; HTTP/1.0 GET: one request per connection, the response read until the
; server closes it.

HTTP_PORT     equ 80
HTTP_REQ_MAX  equ 512
HTTP_IDLE_MS  equ 10000

; name: http_get
; in:   rdi = "http://host:port/path", with the scheme, port and path
;       optional; interrupts on
; out:  the whole response in tcp_rx, tcp_rx_len bytes; CF=1 if the host
;       has no address, refused, the send failed, or the URL is too long
; clobbers: caller-saved
http_get:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    lea rsi, [rel http_scheme]
    mov ecx, 7
    repe cmpsb
    jne .host
    add rbx, 7
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
    mov dword [rel http_port], HTTP_PORT
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
.unsent:
    call tcp_close
.fail:
    stc
.done:
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
http_get_line   db "GET ", 0
http_root       db "/", 0
http_host_line  db " HTTP/1.0", 13, 10, "Host: ", 0
http_tail       db 13, 10, "User-Agent: vitre", 13, 10, "Connection: close", 13, 10, 13, 10, 0
http_msg_size   db 10, "[http] ", 0
http_msg_bytes  db " bytes", 10, 0
http_msg_failed db "[http] no response", 10, 0

section .bss
http_port    resd 1
http_host    resb HTTP_HOST_MAX
http_request resb HTTP_REQ_MAX
section .text
