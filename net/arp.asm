; ARP for IPv4 over Ethernet: answers requests for our address, learns every
; sender it hears from, and resolves addresses on demand.

ARP_HTYPE    equ 0
ARP_PTYPE    equ 2
ARP_HLEN     equ 4
ARP_PLEN     equ 5
ARP_OPER     equ 6
ARP_SHA      equ 8
ARP_SPA      equ 14
ARP_THA      equ 18
ARP_TPA      equ 24
ARP_SIZE     equ 28
ARP_REQUEST  equ 1
ARP_REPLY    equ 2

ARP_ENTRY    equ 16                 ; ip dd, mac 6 bytes, 6 spare
ARP_E_IP     equ 0
ARP_E_MAC    equ 4
ARP_ENTRIES  equ 16
ARP_TRIES    equ 3
ARP_WAIT_MS  equ 500

; name: arp_input
; in:   rdi = ARP packet, esi = length
; out:  the sender learnt; a request for our address answered
; clobbers: caller-saved
arp_input:
    push rbx
    mov rbx, rdi
    cmp esi, ARP_SIZE
    jb .done
    cmp dword [rbx + ARP_HTYPE], 0x00080100     ; Ethernet, IPv4
    jne .done
    cmp word [rbx + ARP_HLEN], 0x0406
    jne .done
    mov edi, [rbx + ARP_SPA]
    lea rsi, [rbx + ARP_SHA]
    call arp_learn
    cmp word [rbx + ARP_OPER], ARP_REQUEST << 8
    jne .done
    mov eax, [rbx + ARP_TPA]
    cmp eax, [rel net_ip]
    jne .done
    lea rsi, [rbx + ARP_SHA]
    mov edi, [rbx + ARP_SPA]
    mov edx, ARP_REPLY
    call arp_send
.done:
    pop rbx
    ret

; name: arp_send
; in:   edx = operation, edi = target IP, rsi = target MAC (the broadcast
;       address for a request)
; out:  the packet sent from our address
; clobbers: caller-saved
arp_send:
    sub rsp, 8
    lea r8, [rel arp_packet]
    mov dword [r8 + ARP_HTYPE], 0x00080100
    mov word [r8 + ARP_HLEN], 0x0406
    xchg dl, dh
    mov [r8 + ARP_OPER], dx
    mov eax, [rel net_mac]
    mov [r8 + ARP_SHA], eax
    mov ax, [rel net_mac + 4]
    mov [r8 + ARP_SHA + 4], ax
    mov eax, [rel net_ip]
    mov [r8 + ARP_SPA], eax
    mov [r8 + ARP_TPA], edi
    mov eax, [rsi]                  ; a request's THA is ignored (RFC 826)
    mov cx, [rsi + 4]
    mov [r8 + ARP_THA], eax
    mov [r8 + ARP_THA + 4], cx
    mov rdi, rsi
    mov esi, ETH_TYPE_ARP
    mov rdx, r8
    mov ecx, ARP_SIZE
    call eth_send
    add rsp, 8
    ret

; name: arp_learn
; in:   edi = IP, rsi = its MAC
; out:  the cache maps the IP to the MAC, replacing the oldest entry when full
; clobbers: rax, rcx, rdx
arp_learn:
    pushfq                          ; the IRQ path learns too
    cli
    test edi, edi
    jz .done
    lea rdx, [rel arp_cache]
    mov ecx, ARP_ENTRIES
.find:
    cmp [rdx + ARP_E_IP], edi
    je .store
    add rdx, ARP_ENTRY
    dec ecx
    jnz .find
    mov eax, [rel arp_next]         ; not cached: take the next slot in turn
    lea ecx, [rax + 1]
    and ecx, ARP_ENTRIES - 1
    mov [rel arp_next], ecx
    shl eax, 4
    lea rdx, [rel arp_cache]
    add rdx, rax
.store:
    mov [rdx + ARP_E_IP], edi
    mov eax, [rsi]
    mov [rdx + ARP_E_MAC], eax
    mov ax, [rsi + 4]
    mov [rdx + ARP_E_MAC + 4], ax
.done:
    popfq
    ret

; name: arp_lookup
; in:   edi = IP
; out:  rax = address of its cached MAC; CF=1 if it is not cached
; clobbers: rax, rcx
arp_lookup:
    lea rax, [rel arp_cache]
    mov ecx, ARP_ENTRIES
.find:
    cmp [rax + ARP_E_IP], edi
    je .found
    add rax, ARP_ENTRY
    dec ecx
    jnz .find
    stc
    ret
.found:
    add rax, ARP_E_MAC
    clc
    ret

; name: arp_resolve
; in:   edi = IP (interrupts on)
; out:  rax = address of its MAC, asking up to ARP_TRIES times; CF=1 if nobody
;       answered
; clobbers: caller-saved
arp_resolve:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, ARP_TRIES
.try:
    mov edi, ebx
    call arp_lookup
    jnc .done
    mov edi, ebx
    lea rsi, [rel arp_broadcast]
    mov edx, ARP_REQUEST
    call arp_send
    mov r13, [rel timer_ticks]
    add r13, ARP_WAIT_MS
.wait:
    mov edi, ebx
    call arp_lookup
    jnc .done
    call task_yield
    cmp [rel timer_ticks], r13
    jb .wait
    dec r12d
    jnz .try
    stc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_arp
; in:   rdi = an IPv4 address to resolve, or nothing to list the cache
; out:  "[arp] 10.0.2.2 is 52:55:0a:00:02:02" per address
; clobbers: caller-saved
cmd_arp:
    push rbx
    push r12
    push r13
    cmp byte [rel net_ready], 0
    je .no_net
    cmp byte [rdi], 0
    je .list
    call net_parse_ip
    jc .usage
    mov ebx, eax
    mov edi, eax
    call arp_resolve
    jc .silent
    mov edi, ebx
    mov rsi, rax
    call arp_put
    jmp .done
.list:
    lea r12, [rel arp_cache]
    mov r13d, ARP_ENTRIES
.entry:
    mov edi, [r12 + ARP_E_IP]
    test edi, edi
    jz .next
    lea rsi, [r12 + ARP_E_MAC]
    call arp_put
.next:
    add r12, ARP_ENTRY
    dec r13d
    jnz .entry
    jmp .done
.silent:
    lea rdi, [rel arp_msg_prefix]
    call kputs
    mov edi, ebx
    call net_put_ip
    lea rdi, [rel arp_msg_silent]
    call kputs
    jmp .done
.usage:
    lea rdi, [rel arp_msg_usage]
    call kputs
    jmp .done
.no_net:
    lea rdi, [rel net_msg_none]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: arp_put
; in:   edi = IP, rsi = its MAC
; out:  "[arp] <ip> is <mac>" printed
; clobbers: caller-saved
arp_put:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12, rsi
    lea rdi, [rel arp_msg_prefix]
    call kputs
    mov edi, ebx
    call net_put_ip
    lea rdi, [rel arp_msg_is]
    call kputs
    mov rdi, r12
    call net_put_mac_at
    mov edi, 10
    call kputc
    add rsp, 8
    pop r12
    pop rbx
    ret

arp_broadcast  db 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
arp_msg_prefix db "[arp] ", 0
arp_msg_is     db " is ", 0
arp_msg_silent db " did not answer", 10, 0
arp_msg_usage  db "usage: arp [a.b.c.d]", 10, 0

section .bss
alignb 8
arp_cache  resb ARP_ENTRY * ARP_ENTRIES
arp_packet resb ARP_SIZE
arp_next   resd 1
section .text
