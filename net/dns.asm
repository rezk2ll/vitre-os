; DNS client: A record lookups through the server DHCP named.

DNS_PORT        equ 53
DNS_CLIENT_PORT equ 49153
DNS_ID          equ 0x5456          ; "VT" as it sits in the packet
DNS_HDR         equ 12
DNS_MAX         equ 512
DNS_WAIT_MS     equ 2000
DNS_TRIES       equ 3
DNS_TYPE_A_IN   equ 0x01000100      ; type 1, class 1, network order

DNS_IDLE    equ 0
DNS_WAITING equ 1
DNS_ANSWER  equ 2
DNS_FAILED  equ 3

; name: dns_skip_name
; in:   rax = encoded name, rcx = end of the message
; out:  rax = the byte after the name; CF=1 if it runs past the end
; clobbers: rax, r8
dns_skip_name:
    cmp rax, rcx
    jae .bad
    movzx r8d, byte [rax]
    test r8d, r8d
    jz .root
    cmp r8d, 0xc0                   ; a pointer ends the name
    jae .pointer
    lea rax, [rax + r8 + 1]
    jmp dns_skip_name
.pointer:
    inc rax                         ; two bytes, the root label one
.root:
    inc rax
    clc
    ret
.bad:
    stc
    ret

; name: dns_input
; in:   rdi = DNS message, esi = length
; out:  the first A record of the answer to our query recorded, or the
;       query marked failed
; clobbers: caller-saved
dns_input:
    cmp esi, DNS_HDR
    jb .drop
    cmp word [rdi], DNS_ID
    jne .drop
    cmp byte [rel dns_state], DNS_WAITING
    jne .drop
    test byte [rdi + 2], 0x80       ; a response
    jz .drop
    test byte [rdi + 3], 0x0f       ; response code
    jnz .failed
    lea rcx, [rdi + rsi]
    movzx r11d, word [rdi + 6]      ; answer count
    rol r11w, 8
    lea rax, [rdi + DNS_HDR]        ; skip our one question
    call dns_skip_name
    jc .failed
    add rax, 4
.answer:
    test r11d, r11d
    jz .failed
    call dns_skip_name
    jc .failed
    lea r8, [rax + 10]
    cmp r8, rcx
    ja .failed
    movzx r9d, word [rax + 8]
    rol r9w, 8
    lea r10, [r8 + r9]
    cmp r10, rcx
    ja .failed
    cmp dword [rax], DNS_TYPE_A_IN
    jne .next
    cmp r9d, 4
    jne .next
    mov eax, [r8]
    mov [rel dns_address], eax
    mov byte [rel dns_state], DNS_ANSWER
    ret
.next:
    mov rax, r10
    dec r11d
    jmp .answer
.failed:
    mov byte [rel dns_state], DNS_FAILED
.drop:
    ret

; name: dns_resolve
; in:   rdi = host name, zero-terminated; interrupts on
; out:  eax = its address, network order; CF=1 if it has none or no server
;       answered
; clobbers: caller-saved
dns_resolve:
    push rbx
    push r12
    push r13
    lea rbx, [rel dns_query]
    mov dword [rbx], DNS_ID | (0x0001 << 16)    ; recursion desired
    mov dword [rbx + 4], 0x00000100             ; one question
    mov dword [rbx + 8], 0
    lea rdx, [rbx + DNS_HDR]        ; where the current label's length goes
    lea rcx, [rdx + 1]
.char:
    lea rax, [rbx + DNS_MAX - 6]
    cmp rcx, rax
    jae .fail
    mov al, [rdi]
    inc rdi
    cmp al, '.'
    je .label
    test al, al
    jz .label
    mov [rcx], al
    inc rcx
    jmp .char
.label:
    mov r8, rcx
    sub r8, rdx
    dec r8
    jz .fail                        ; empty label
    cmp r8, 63
    ja .fail
    mov [rdx], r8b
    mov rdx, rcx
    inc rcx
    test al, al
    jnz .char
    mov byte [rdx], 0
    mov dword [rcx], DNS_TYPE_A_IN
    add rcx, 4
    sub rcx, rbx
    mov r13d, ecx                   ; query length
    mov r12d, DNS_TRIES
.send:
    mov byte [rel dns_state], DNS_WAITING
    mov edi, [rel net_dns]
    mov esi, DNS_CLIENT_PORT
    mov r8d, DNS_PORT
    mov rdx, rbx
    mov ecx, r13d
    call udp_send
    mov rbx, [rel timer_ticks]
    add rbx, DNS_WAIT_MS
.wait:
    cmp byte [rel dns_state], DNS_ANSWER
    je .found
    cmp byte [rel dns_state], DNS_FAILED
    je .fail
    call task_yield
    cmp [rel timer_ticks], rbx
    jb .wait
    lea rbx, [rel dns_query]
    dec r12d
    jnz .send
.fail:
    mov byte [rel dns_state], DNS_IDLE
    stc
    jmp .done
.found:
    mov byte [rel dns_state], DNS_IDLE
    mov eax, [rel dns_address]
    clc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: net_resolve
; in:   rdi = "a.b.c.d" or a host name; interrupts on
; out:  eax = the address, network order; CF=1 if it has none
; clobbers: caller-saved
net_resolve:
    push rdi
    call net_parse_ip
    pop rdi
    jnc .done
    jmp dns_resolve
.done:
    ret

; name: cmd_host
; in:   rdi = host name
; out:  "[dns] name is a.b.c.d", or why not
; clobbers: caller-saved
cmd_host:
    push rbx
    mov rbx, rdi
    cmp byte [rel net_ready], 0
    je .no_net
    cmp byte [rdi], 0
    je .usage
    call dns_resolve
    jc .unknown
    push rax
    lea rdi, [rel dns_msg]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel dns_msg_is]
    call kputs
    pop rdi
    call net_put_ip
    mov edi, 10
    call kputc
    jmp .done
.unknown:
    lea rdi, [rel dns_msg]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel dns_msg_unknown]
    jmp .print
.usage:
    lea rdi, [rel dns_msg_usage]
    jmp .print
.no_net:
    lea rdi, [rel net_msg_none]
.print:
    call kputs
.done:
    pop rbx
    ret

dns_msg         db "[dns] ", 0
dns_msg_is      db " is ", 0
dns_msg_unknown db " has no address", 10, 0
dns_msg_usage   db "usage: host name", 10, 0

section .bss
alignb 8
dns_query   resb DNS_MAX
dns_address resd 1
dns_state   resb 1
section .text
