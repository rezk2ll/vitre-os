; Ethernet II framing, and IPv4 addresses as text. Addresses and ports are
; kept in network byte order, as they sit in the packet.

ETH_HDR       equ 14
ETH_DST       equ 0
ETH_SRC       equ 6
ETH_TYPE      equ 12
ETH_TYPE_ARP  equ 0x0806
ETH_TYPE_IPV4 equ 0x0800
ETH_MIN       equ 60                ; shorter frames are padded

; name: eth_input
; in:   rdi = frame, esi = length
; out:  the payload handed to its protocol; other frames are dropped
; clobbers: caller-saved
eth_input:
    cmp esi, ETH_HDR
    jb .drop
    movzx eax, word [rdi + ETH_TYPE]
    xchg al, ah
    add rdi, ETH_HDR
    sub esi, ETH_HDR
    cmp eax, ETH_TYPE_ARP
    je arp_input
    cmp eax, ETH_TYPE_IPV4
    je ip_input
.drop:
    ret

; name: eth_send
; in:   rdi = destination MAC, esi = ether type, rdx = payload, ecx = length
;       (at most ETH_FRAME_MAX - ETH_HDR)
; out:  the frame queued; CF=1 if the card did not take it
; clobbers: caller-saved
eth_send:
    pushfq                          ; eth_frame is shared with the IRQ path
    cli
    lea r8, [rel eth_frame]
    mov eax, [rdi]
    mov [r8 + ETH_DST], eax
    mov ax, [rdi + 4]
    mov [r8 + ETH_DST + 4], ax
    mov eax, [rel net_mac]
    mov [r8 + ETH_SRC], eax
    mov ax, [rel net_mac + 4]
    mov [r8 + ETH_SRC + 4], ax
    mov eax, esi
    xchg al, ah
    mov [r8 + ETH_TYPE], ax
    lea rdi, [r8 + ETH_HDR]
    mov rsi, rdx
    mov edx, ecx
    rep movsb
    add edx, ETH_HDR
    cmp edx, ETH_MIN
    jae .send
    mov ecx, ETH_MIN
    sub ecx, edx
    xor eax, eax
    rep stosb
    mov edx, ETH_MIN
.send:
    mov rdi, r8
    mov esi, edx
    call e1000_send
    jc .failed
    popfq
    clc
    ret
.failed:
    popfq
    stc
    ret

; name: net_put_ip
; in:   edi = IPv4 address, network order
; out:  printed as "10.0.2.15"
; clobbers: caller-saved
net_put_ip:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, 4
.byte:
    movzx edi, bl
    call [rel jt_kput_dec]
    shr ebx, 8
    dec r12d
    jz .done
    mov edi, '.'
    call kputc
    jmp .byte
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: net_parse_ip
; in:   rdi = "a.b.c.d", zero-terminated
; out:  eax = the address, network order; CF=1 if it is not one
; clobbers: rax, rcx, rdx, rdi, rsi
net_parse_ip:
    xor esi, esi                    ; address so far
    xor ecx, ecx                    ; shift for the next byte
.byte:
    xor edx, edx
    movzx eax, byte [rdi]
    sub eax, '0'
    cmp eax, 9
    ja .bad                         ; each byte needs a digit
.digit:
    imul edx, edx, 10
    add edx, eax
    cmp edx, 255
    ja .bad
    inc rdi
    movzx eax, byte [rdi]
    sub eax, '0'
    cmp eax, 9
    jbe .digit
    shl edx, cl
    or esi, edx
    add ecx, 8
    movzx eax, byte [rdi]
    inc rdi
    cmp ecx, 32
    je .end
    cmp eax, '.'
    je .byte
.bad:
    stc
    ret
.end:
    test eax, eax
    jnz .bad
    mov eax, esi
    clc
    ret

section .bss
eth_frame resb ETH_FRAME_MAX
section .text
