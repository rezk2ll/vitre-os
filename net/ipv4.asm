; IPv4: unfragmented packets to and from our one address.

IP_HDR      equ 20
IP_VER_IHL  equ 0
IP_LEN      equ 2
IP_ID       equ 4
IP_FRAG     equ 6
IP_TTL      equ 8
IP_PROTO    equ 9
IP_SUM      equ 10
IP_SRC      equ 12
IP_DST      equ 16
IP_PROTO_ICMP equ 1
IP_MTU      equ 1500

; name: net_checksum
; in:   rdi = data, esi = length in bytes
; out:  ax = the Internet checksum, ready to store as is
; clobbers: rax, r8, r9, r10
net_checksum:
    mov r8, rdi
    mov r9d, esi
    xor eax, eax
.word:
    cmp r9d, 2
    jb .odd
    movzx r10d, word [r8]
    add eax, r10d
    add r8, 2
    sub r9d, 2
    jmp .word
.odd:
    test r9d, r9d
    jz .fold
    movzx r10d, byte [r8]           ; the last byte pads with a zero
    add eax, r10d
.fold:
    mov r10d, eax
    shr r10d, 16
    jz .done
    and eax, 0xffff
    add eax, r10d
    jmp .fold
.done:
    not ax
    ret

; name: ip_input
; in:   rdi = packet, esi = length
; out:  a packet for us handed to its protocol; others dropped
; clobbers: caller-saved
ip_input:
    cmp esi, IP_HDR
    jb .drop
    movzx eax, byte [rdi + IP_VER_IHL]
    mov ecx, eax
    shr eax, 4
    cmp eax, 4
    jne .drop
    and ecx, 15
    shl ecx, 2                      ; header length in bytes
    cmp ecx, IP_HDR
    jb .drop
    cmp ecx, esi
    ja .drop
    mov r11d, esi
    mov esi, ecx
    call net_checksum
    mov esi, r11d
    test ax, ax                     ; a valid header sums to zero
    jnz .drop
    movzx eax, word [rdi + IP_LEN]
    xchg al, ah
    cmp eax, esi                    ; the frame may carry padding after it
    ja .drop
    cmp eax, ecx
    jb .drop
    test word [rdi + IP_FRAG], 0xff3f   ; more fragments, or an offset
    jnz .drop
    mov edx, [rdi + IP_DST]
    cmp edx, [rel net_ip]
    je .ours
    cmp edx, 0xffffffff             ; DHCP answers come broadcast
    jne .drop
.ours:
    movzx r8d, byte [rdi + IP_PROTO]
    mov edx, [rdi + IP_SRC]
    mov esi, eax
    sub esi, ecx
    add rdi, rcx
    cmp r8d, IP_PROTO_ICMP
    je icmp_input
    cmp r8d, IP_PROTO_UDP
    je udp_input
.drop:
    ret

; name: ip_send
; in:   edi = destination, esi = protocol, rdx = payload, ecx = length
;       (at most IP_MTU - IP_HDR)
; out:  the packet sent; CF=1 if the next hop has no known MAC or the card
;       refused it. Outside an IRQ an unknown next hop is resolved first
; clobbers: caller-saved
ip_send:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    call ip_route
    jc .fail
    mov r15, rax                    ; next hop MAC
    pushfq                          ; ip_packet is shared with the IRQ path
    cli
    lea rdi, [rel ip_packet]
    mov byte [rdi + IP_VER_IHL], 0x45
    mov byte [rdi + IP_VER_IHL + 1], 0
    lea eax, [r14 + IP_HDR]
    xchg al, ah
    mov [rdi + IP_LEN], ax
    inc word [rel ip_next_id]
    mov ax, [rel ip_next_id]
    xchg al, ah
    mov [rdi + IP_ID], ax
    mov word [rdi + IP_FRAG], 0x0040    ; don't fragment
    mov byte [rdi + IP_TTL], 64
    mov [rdi + IP_PROTO], r12b
    mov word [rdi + IP_SUM], 0
    mov eax, [rel net_ip]
    mov [rdi + IP_SRC], eax
    mov [rdi + IP_DST], ebx
    mov esi, IP_HDR
    call net_checksum
    lea rdi, [rel ip_packet]
    mov [rdi + IP_SUM], ax
    add rdi, IP_HDR
    mov rsi, r13
    mov ecx, r14d
    rep movsb
    mov rdi, r15
    mov esi, ETH_TYPE_IPV4
    lea rdx, [rel ip_packet]
    lea ecx, [r14 + IP_HDR]
    call eth_send
    jc .refused
    popfq
    clc
    jmp .done
.refused:
    popfq
.fail:
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: ip_route
; in:   edi = destination
; out:  rax = address of the next hop's MAC; CF=1 if it is unknown. Outside
;       an IRQ an unknown next hop is resolved first
; clobbers: caller-saved
ip_route:
    push rbx
    lea rax, [rel arp_broadcast]
    cmp edi, 0xffffffff
    je .done                        ; CF=0 from the equal compare
    mov eax, edi                    ; next hop: the host itself on our subnet
    xor eax, [rel net_ip]
    test eax, [rel net_mask]
    jz .hop
    mov edi, [rel net_gateway]
.hop:
    mov ebx, edi
    call arp_lookup
    jnc .done
    pushfq
    pop rax
    test eax, 1 << 9                ; IF clear: called from an IRQ, cannot wait
    stc
    jz .done
    mov edi, ebx
    call arp_resolve
.done:
    pop rbx
    ret

section .bss
alignb 8
ip_packet  resb IP_MTU
ip_next_id resw 1
section .text
