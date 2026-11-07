; Network state shared by the driver and the protocol layers, and the `net`
; command.

; name: net_init
; in:   none
; out:  the e1000 brought up, or "[net] no network card" logged
; clobbers: caller-saved
net_init:
    sub rsp, 8
    call e1000_init
    jnc .done
    lea rdi, [rel net_msg_none]
    call kputs
.done:
    add rsp, 8
    ret

; name: net_put_mac
; in:   none
; out:  net_mac printed as "52:54:00:12:34:56"
; clobbers: caller-saved
net_put_mac:
    push rbx
    xor ebx, ebx
.byte:
    lea rax, [rel net_mac]
    movzx edi, byte [rax + rbx]
    mov esi, 2
    call kput_hexn
    inc ebx
    cmp ebx, 6
    je .done
    mov edi, ':'
    call kputc
    jmp .byte
.done:
    pop rbx
    ret

; name: cmd_net
; in:   rdi = arguments (ignored)
; out:  the MAC, link state and frame counters
; clobbers: caller-saved
cmd_net:
    sub rsp, 8
    cmp byte [rel net_ready], 0
    je .none
    lea rdi, [rel net_msg_mac]
    call kputs
    call net_put_mac
    lea rdi, [rel net_msg_link_down]
    call e1000_link_up
    jz .link
    lea rdi, [rel net_msg_link_up]
.link:
    call kputs
    mov rdi, [rel net_rx_frames]
    call [rel jt_kput_dec]
    lea rdi, [rel net_msg_tx]
    call kputs
    mov rdi, [rel net_tx_frames]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    add rsp, 8
    ret
.none:
    lea rdi, [rel net_msg_none]
    call kputs
    add rsp, 8
    ret

; name: eth_input
; in:   rdi = frame, esi = length
; out:  none; frames are only counted until a protocol layer handles them
; clobbers: none
eth_input:
    ret

net_msg_none      db "[net] no network card", 10, 0
net_msg_mac       db "[net] mac ", 0
net_msg_link_up   db ", link up, rx ", 0
net_msg_link_down db ", link down, rx ", 0
net_msg_tx        db " frames, tx ", 0

section .bss
net_mac       resb 6
net_ready     resb 1
alignb 8
net_rx_frames resq 1
net_tx_frames resq 1
section .text
