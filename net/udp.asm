; UDP: datagrams handed to the protocol that owns their port. Checksums are
; left at 0 on send (allowed over IPv4) and not checked on receive.

UDP_SRC      equ 0
UDP_DST      equ 2
UDP_LEN      equ 4
UDP_SUM      equ 6
UDP_HDR      equ 8
IP_PROTO_UDP equ 17
UDP_MAX      equ IP_MTU - IP_HDR - UDP_HDR

; name: udp_input
; in:   rdi = datagram, esi = length, edx = sender
; out:  the payload handed to the owner of its port; others dropped
; clobbers: caller-saved
udp_input:
    cmp esi, UDP_HDR
    jb .drop
    movzx eax, word [rdi + UDP_LEN]
    xchg al, ah
    cmp eax, esi
    ja .drop
    cmp eax, UDP_HDR
    jb .drop
    movzx ecx, word [rdi + UDP_DST]
    xchg cl, ch
    lea esi, [rax - UDP_HDR]
    add rdi, UDP_HDR
    cmp ecx, DHCP_CLIENT_PORT
    je dhcp_input
.drop:
    ret

; name: udp_send
; in:   edi = destination, esi = source port, r8d = destination port,
;       rdx = payload, ecx = length (at most UDP_MAX)
; out:  the datagram sent; CF as ip_send
; clobbers: caller-saved
udp_send:
    lea rax, [rel udp_packet]
    rol si, 8
    mov [rax + UDP_SRC], si
    rol r8w, 8
    mov [rax + UDP_DST], r8w
    lea r10d, [rcx + UDP_HDR]
    mov r9d, r10d
    rol r9w, 8
    mov [rax + UDP_LEN], r9w
    mov word [rax + UDP_SUM], 0
    mov r11d, edi
    lea rdi, [rax + UDP_HDR]
    mov rsi, rdx
    rep movsb
    mov edi, r11d
    mov esi, IP_PROTO_UDP
    mov rdx, rax
    mov ecx, r10d
    jmp ip_send

section .bss
alignb 8
udp_packet resb IP_MTU - IP_HDR
section .text
