; DHCP client: discover, request, and take the address, mask, gateway and
; DNS server from the acknowledgement.

DHCP_CLIENT_PORT equ 68
DHCP_SERVER_PORT equ 67
DHCP_XID_AT      equ 4
DHCP_FLAGS       equ 10
DHCP_YIADDR      equ 16
DHCP_CHADDR      equ 28
DHCP_MAGIC_AT    equ 236
DHCP_OPTIONS     equ 240
DHCP_MSG_LEN     equ 300
DHCP_MAGIC       equ 0x63538263     ; 99.130.83.99 as it sits in the packet
DHCP_XID         equ 0x52544956     ; "VITR"
DHCP_BOOTREPLY   equ 2
DHCP_DISCOVER    equ 1
DHCP_OFFER       equ 2
DHCP_REQUEST     equ 3
DHCP_ACK         equ 5
DHCP_WAIT_MS     equ 2000
DHCP_TRIES       equ 3

; dhcp_state: what the client waits for next.
DHCP_IDLE     equ 0
DHCP_WANT_OFFER equ 1
DHCP_GOT_OFFER  equ 2
DHCP_WANT_ACK   equ 3
DHCP_GOT_ACK    equ 4

; name: dhcp_option
; in:   rdi = DHCP message, esi = length, edx = option code
; out:  rax = the option's value, r10 = its length; CF=1 if the message
;       does not carry it
; clobbers: rax, rcx, r8, r9, r10
dhcp_option:
    lea rax, [rdi + DHCP_OPTIONS]
    lea rcx, [rdi + rsi]
.next:
    cmp rax, rcx
    jae .none
    movzx r8d, byte [rax]
    cmp r8d, 255
    je .none
    test r8d, r8d                   ; pad
    jnz .option
    inc rax
    jmp .next
.option:
    lea r9, [rax + 2]
    cmp r9, rcx
    ja .none
    movzx r10d, byte [rax + 1]
    add r9, r10
    cmp r9, rcx
    ja .none
    cmp r8d, edx
    je .found
    mov rax, r9
    jmp .next
.found:
    add rax, 2
    clc
    ret
.none:
    stc
    ret

; name: dhcp_dword
; in:   as dhcp_option
; out:  eax = the option's first 4 bytes; CF=1 if it is missing or shorter
; clobbers: rax, rcx, r8, r9, r10
dhcp_dword:
    call dhcp_option
    jc .done
    cmp r10d, 4
    jb .done
    mov eax, [rax]
.done:
    ret

; name: dhcp_input
; in:   rdi = DHCP message, esi = length
; out:  an offer or acknowledgement for our transaction recorded
; clobbers: caller-saved
dhcp_input:
    cmp esi, DHCP_OPTIONS
    jb .drop
    cmp byte [rdi], DHCP_BOOTREPLY
    jne .drop
    cmp dword [rdi + DHCP_XID_AT], DHCP_XID
    jne .drop
    cmp dword [rdi + DHCP_MAGIC_AT], DHCP_MAGIC
    jne .drop
    push rbx
    mov rbx, rdi
    mov edx, 53                     ; message type
    call dhcp_option
    jc .done
    mov edx, [rbx + DHCP_YIADDR]
    mov cl, [rax]
    cmp cl, DHCP_OFFER
    je .offer
    cmp cl, DHCP_ACK
    jne .done
    cmp byte [rel dhcp_state], DHCP_WANT_ACK
    jne .done
    mov [rel dhcp_ip], edx
    mov rdi, rbx
    mov edx, 1
    call dhcp_dword
    jc .router
    mov [rel dhcp_mask], eax
.router:
    mov rdi, rbx
    mov edx, 3
    call dhcp_dword
    jc .dns
    mov [rel dhcp_router], eax
.dns:
    mov rdi, rbx
    mov edx, 6
    call dhcp_dword
    jc .acked
    mov [rel net_dns], eax
.acked:
    mov byte [rel dhcp_state], DHCP_GOT_ACK
    jmp .done
.offer:
    cmp byte [rel dhcp_state], DHCP_WANT_OFFER
    jne .done
    mov [rel dhcp_ip], edx
    mov rdi, rbx
    mov edx, 54                     ; server identifier
    call dhcp_dword
    jc .done
    mov [rel dhcp_server], eax
    mov byte [rel dhcp_state], DHCP_GOT_OFFER
.done:
    pop rbx
.drop:
    ret

; name: dhcp_send
; in:   dl = DHCP_DISCOVER or DHCP_REQUEST
; out:  the message broadcast; CF as ip_send
; clobbers: caller-saved
dhcp_send:
    push rbx
    lea rbx, [rel dhcp_msg]
    mov rdi, rbx
    mov ecx, DHCP_MSG_LEN
    xor eax, eax
    rep stosb
    mov dword [rbx], 0x00060101     ; request, Ethernet, 6-byte address
    mov dword [rbx + DHCP_XID_AT], DHCP_XID
    mov word [rbx + DHCP_FLAGS], 0x0080 ; replies broadcast: we may have no address
    mov eax, [rel net_mac]
    mov [rbx + DHCP_CHADDR], eax
    mov ax, [rel net_mac + 4]
    mov [rbx + DHCP_CHADDR + 4], ax
    mov dword [rbx + DHCP_MAGIC_AT], DHCP_MAGIC
    lea rdi, [rbx + DHCP_OPTIONS]
    mov word [rdi], 0x0135          ; message type, length 1
    mov [rdi + 2], dl
    add rdi, 3
    cmp dl, DHCP_REQUEST
    jne .params
    mov word [rdi], 0x0432          ; requested address
    mov eax, [rel dhcp_ip]
    mov [rdi + 2], eax
    mov word [rdi + 6], 0x0436      ; server identifier
    mov eax, [rel dhcp_server]
    mov [rdi + 8], eax
    add rdi, 12
.params:
    mov dword [rdi], 0x03010337     ; ask for mask, router, DNS
    mov word [rdi + 4], 0xff06
    mov edi, 0xffffffff
    mov esi, DHCP_CLIENT_PORT
    mov r8d, DHCP_SERVER_PORT
    mov rdx, rbx
    mov ecx, DHCP_MSG_LEN
    call udp_send
    pop rbx
    ret

; name: dhcp_exchange
; in:   dl = message to send, dh = state that answers it
; out:  CF=1 if no answer came after DHCP_TRIES sends
; clobbers: caller-saved
dhcp_exchange:
    push rbx
    push r12
    push r13
    mov ebx, edx
    mov r13d, DHCP_TRIES
.send:
    mov byte [rel dhcp_state], bh
    dec byte [rel dhcp_state]       ; the state before an answer
    mov edx, ebx
    call dhcp_send
    mov r12, [rel timer_ticks]
    add r12, DHCP_WAIT_MS
.wait:
    cmp [rel dhcp_state], bh
    je .done                        ; CF=0 from the equal compare
    call task_yield
    cmp [rel timer_ticks], r12
    jb .wait
    dec r13d
    jnz .send
    stc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_dhcp
; in:   interrupts on
; out:  the lease applied and printed, or "[dhcp] no answer"
; clobbers: caller-saved
cmd_dhcp:
    sub rsp, 8
    cmp byte [rel net_ready], 0
    je .no_net
    mov edx, DHCP_DISCOVER | (DHCP_GOT_OFFER << 8)
    call dhcp_exchange
    jc .no_answer
    mov edx, DHCP_REQUEST | (DHCP_GOT_ACK << 8)
    call dhcp_exchange
    jc .no_answer
    mov eax, [rel dhcp_ip]
    mov [rel net_ip], eax
    mov eax, [rel dhcp_mask]
    mov [rel net_mask], eax
    mov eax, [rel dhcp_router]
    mov [rel net_gateway], eax
    lea rdi, [rel dhcp_msg_lease]
    call kputs
    mov edi, [rel net_ip]
    call net_put_ip
    lea rdi, [rel dhcp_msg_gateway]
    call kputs
    mov edi, [rel net_gateway]
    call net_put_ip
    lea rdi, [rel dhcp_msg_dns]
    call kputs
    mov edi, [rel net_dns]
    call net_put_ip
    mov edi, 10
    call kputc
    jmp .done
.no_answer:
    lea rdi, [rel dhcp_msg_none]
    call kputs
    jmp .done
.no_net:
    lea rdi, [rel net_msg_none]
    call kputs
.done:
    mov byte [rel dhcp_state], DHCP_IDLE
    add rsp, 8
    ret

dhcp_msg_lease   db "[dhcp] lease ", 0
dhcp_msg_gateway db ", gateway ", 0
dhcp_msg_dns     db ", dns ", 0
dhcp_msg_none    db "[dhcp] no answer", 10, 0

section .bss
alignb 8
dhcp_msg    resb DHCP_MSG_LEN
dhcp_ip     resd 1
dhcp_server resd 1
dhcp_mask   resd 1
dhcp_router resd 1
dhcp_state  resb 1
section .text
