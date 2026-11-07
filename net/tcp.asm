; TCP: one client connection at a time. Received data lands in order in
; tcp_rx; anything out of order is dropped and acknowledged again so the
; peer resends it. Sequence numbers are kept in host order.

TCP_SRC     equ 0
TCP_DST     equ 2
TCP_SEQ     equ 4
TCP_ACK     equ 8
TCP_OFF     equ 12
TCP_FLAGS   equ 13
TCP_WIN     equ 14
TCP_SUM     equ 16
TCP_HDR     equ 20
TCP_F_FIN   equ 1
TCP_F_SYN   equ 2
TCP_F_RST   equ 4
TCP_F_PSH   equ 8
TCP_F_ACK   equ 16
IP_PROTO_TCP equ 6
TCP_MSS     equ 1024
TCP_RX_SIZE equ 256 * 1024
TCP_WAIT_MS equ 1000
TCP_TRIES   equ 5

TCP_CLOSED      equ 0
TCP_SYN_SENT    equ 1
TCP_ESTABLISHED equ 2

; name: tcp_checksum
; in:   rdi = segment, esi = length, edx = source, ecx = destination
; out:  ax = the checksum over the pseudo header and the segment
; clobbers: rax, rcx, rdx, r8, r9, r10
tcp_checksum:
    movzx eax, dx
    shr edx, 16
    add eax, edx
    movzx edx, cx
    add eax, edx
    shr ecx, 16
    add eax, ecx
    add eax, IP_PROTO_TCP << 8
    mov edx, esi
    rol dx, 8
    add eax, edx
    jmp net_checksum_add

; name: tcp_segment
; in:   dl = flags, rsi = data, ecx = length (at most TCP_MSS)
; out:  a segment at tcp_snd_nxt sent to the peer, acknowledging
;       tcp_rcv_nxt; sequence numbers are not advanced
; clobbers: caller-saved
tcp_segment:
    push rbx
    push r12
    push r13
    pushfq                          ; tcp_packet is shared with the IRQ path
    cli
    mov ebx, edx
    mov r12, rsi
    mov r13d, ecx
    lea rdi, [rel tcp_packet]
    mov eax, [rel tcp_local_port]
    rol ax, 8
    mov [rdi + TCP_SRC], ax
    mov eax, [rel tcp_peer_port]
    rol ax, 8
    mov [rdi + TCP_DST], ax
    mov eax, [rel tcp_snd_nxt]
    bswap eax
    mov [rdi + TCP_SEQ], eax
    mov eax, [rel tcp_rcv_nxt]
    bswap eax
    mov [rdi + TCP_ACK], eax
    mov byte [rdi + TCP_OFF], (TCP_HDR / 4) << 4
    mov [rdi + TCP_FLAGS], bl
    mov eax, TCP_RX_SIZE            ; window: the room left in tcp_rx
    sub eax, [rel tcp_rx_len]
    mov ecx, 0xffff
    cmp eax, ecx
    cmova eax, ecx
    rol ax, 8
    mov [rdi + TCP_WIN], ax
    mov dword [rdi + TCP_SUM], 0    ; and the urgent pointer
    add rdi, TCP_HDR
    mov rsi, r12
    mov ecx, r13d
    rep movsb
    lea rdi, [rel tcp_packet]
    lea esi, [r13 + TCP_HDR]
    mov edx, [rel net_ip]
    mov ecx, [rel tcp_peer]
    call tcp_checksum
    mov [rel tcp_packet + TCP_SUM], ax
    mov edi, [rel tcp_peer]
    mov esi, IP_PROTO_TCP
    lea rdx, [rel tcp_packet]
    lea ecx, [r13 + TCP_HDR]
    call ip_send
    popfq
    pop r13
    pop r12
    pop rbx
    ret

; name: tcp_input
; in:   rdi = segment, esi = length, edx = sender
; out:  the connection's state and acknowledgements updated
; clobbers: caller-saved
tcp_input:
    cmp esi, TCP_HDR
    jb .drop
    cmp byte [rel tcp_state], TCP_CLOSED
    je .drop
    cmp edx, [rel tcp_peer]
    jne .drop
    movzx eax, word [rdi + TCP_SRC]
    rol ax, 8
    cmp eax, [rel tcp_peer_port]
    jne .drop
    movzx eax, word [rdi + TCP_DST]
    rol ax, 8
    cmp eax, [rel tcp_local_port]
    jne .drop
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov ecx, [rel net_ip]
    call tcp_checksum
    test ax, ax
    jnz .done
    movzx r13d, byte [rbx + TCP_OFF]
    shr r13d, 4
    shl r13d, 2                     ; header length
    cmp r13d, TCP_HDR
    jb .done
    cmp r13d, r12d
    ja .done
    mov al, [rbx + TCP_FLAGS]
    test al, TCP_F_RST
    jnz .reset
    cmp byte [rel tcp_state], TCP_SYN_SENT
    jne .established
    and al, TCP_F_SYN | TCP_F_ACK
    cmp al, TCP_F_SYN | TCP_F_ACK
    jne .done
    mov eax, [rbx + TCP_ACK]
    bswap eax
    cmp eax, [rel tcp_snd_nxt]
    jne .done
    mov [rel tcp_snd_una], eax
    mov eax, [rbx + TCP_SEQ]
    bswap eax
    inc eax
    mov [rel tcp_rcv_nxt], eax
    mov byte [rel tcp_state], TCP_ESTABLISHED
    jmp .ack
.established:
    test al, TCP_F_ACK
    jz .data
    mov eax, [rbx + TCP_ACK]
    bswap eax
    mov ecx, eax                    ; take it only if it covers sent bytes
    sub ecx, [rel tcp_snd_una]
    mov edx, [rel tcp_snd_nxt]
    sub edx, [rel tcp_snd_una]
    cmp ecx, edx
    ja .data
    mov [rel tcp_snd_una], eax
.data:
    sub r12d, r13d                  ; payload length
    mov eax, [rbx + TCP_SEQ]
    bswap eax
    cmp eax, [rel tcp_rcv_nxt]
    jne .out_of_order
    mov ecx, TCP_RX_SIZE
    sub ecx, [rel tcp_rx_len]
    cmp r12d, ecx
    ja .ack                         ; no room: the peer resends later
    lea rsi, [rbx + r13]
    lea rdi, [rel tcp_rx]
    mov eax, [rel tcp_rx_len]
    add rdi, rax
    mov ecx, r12d
    rep movsb
    add [rel tcp_rx_len], r12d
    add [rel tcp_rcv_nxt], r12d
    test byte [rbx + TCP_FLAGS], TCP_F_FIN
    jnz .fin
    test r12d, r12d
    jz .done                        ; a bare ACK needs no answer
    jmp .ack
.fin:
    inc dword [rel tcp_rcv_nxt]
    mov byte [rel tcp_peer_closed], 1
    jmp .ack
.out_of_order:
    test r12d, r12d
    jnz .ack
    test byte [rbx + TCP_FLAGS], TCP_F_FIN
    jz .done
.ack:
    mov edx, TCP_F_ACK
    xor ecx, ecx
    call tcp_segment
    jmp .done
.reset:
    mov byte [rel tcp_state], TCP_CLOSED
    mov byte [rel tcp_peer_closed], 1
.done:
    pop r13
    pop r12
    pop rbx
.drop:
    ret

; name: tcp_wait_acked
; in:   interrupts on
; out:  CF=1 if the peer did not acknowledge everything sent within
;       TCP_WAIT_MS, or the connection was reset
; clobbers: caller-saved
tcp_wait_acked:
    push rbx
    mov rbx, [rel timer_ticks]
    add rbx, TCP_WAIT_MS
.wait:
    cmp byte [rel tcp_state], TCP_CLOSED
    je .fail
    mov eax, [rel tcp_snd_una]
    cmp eax, [rel tcp_snd_nxt]
    je .done                        ; CF=0 from the equal compare
    call task_yield
    cmp [rel timer_ticks], rbx
    jb .wait
.fail:
    stc
.done:
    pop rbx
    ret

; name: tcp_connect
; in:   edi = address, esi = port; interrupts on
; out:  the connection established; CF=1 if the peer refused it or never
;       answered
; clobbers: caller-saved
tcp_connect:
    push rbx
    mov [rel tcp_peer], edi
    mov [rel tcp_peer_port], esi
    call ip_route                   ; resolve the next hop while we may wait
    jc .done
    inc word [rel tcp_next_port]
    movzx eax, word [rel tcp_next_port]
    or eax, 0xc000                  ; ephemeral range
    mov [rel tcp_local_port], eax
    mov eax, [rel timer_ticks]
    imul eax, eax, -1640531535      ; initial sequence: spread out the clock
    mov [rel tcp_snd_una], eax
    mov [rel tcp_snd_nxt], eax
    mov dword [rel tcp_rcv_nxt], 0
    mov dword [rel tcp_rx_len], 0
    mov byte [rel tcp_peer_closed], 0
    mov byte [rel tcp_state], TCP_SYN_SENT
    mov ebx, TCP_TRIES
.syn:
    mov edx, TCP_F_SYN
    xor ecx, ecx
    call tcp_segment
    inc dword [rel tcp_snd_nxt]
    call tcp_wait_acked
    jnc .done
    cmp byte [rel tcp_state], TCP_CLOSED
    je .refused
    dec dword [rel tcp_snd_nxt]
    dec ebx
    jnz .syn
    mov byte [rel tcp_state], TCP_CLOSED
.refused:
    stc
.done:
    pop rbx
    ret

; name: tcp_close
; in:   interrupts on
; out:  our FIN sent and, within TCP_WAIT_MS, acknowledged; the connection
;       is closed either way
; clobbers: caller-saved
tcp_close:
    sub rsp, 8
    cmp byte [rel tcp_state], TCP_ESTABLISHED
    jne .closed
    mov edx, TCP_F_FIN | TCP_F_ACK
    xor ecx, ecx
    call tcp_segment
    inc dword [rel tcp_snd_nxt]
    call tcp_wait_acked
.closed:
    mov byte [rel tcp_state], TCP_CLOSED
    add rsp, 8
    ret

; name: tcp_write
; in:   rsi = data, ecx = length; interrupts on
; out:  everything sent and acknowledged, one TCP_MSS segment at a time;
;       CF=1 if a segment went unacknowledged TCP_TRIES times or the
;       connection was reset
; clobbers: caller-saved
tcp_write:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rsi
    mov r13d, ecx
.segment:
    test r13d, r13d
    jz .done                        ; CF=0 from the test
    mov ebx, TCP_MSS
    cmp r13d, ebx
    cmovb ebx, r13d
    mov r14d, TCP_TRIES
.send:
    mov edx, TCP_F_PSH | TCP_F_ACK
    mov rsi, r12
    mov ecx, ebx
    call tcp_segment
    add [rel tcp_snd_nxt], ebx
    call tcp_wait_acked
    jnc .next
    cmp byte [rel tcp_state], TCP_CLOSED
    je .fail
    sub [rel tcp_snd_nxt], ebx
    dec r14d
    jnz .send
.fail:
    stc
    jmp .done
.next:
    add r12, rbx
    sub r13d, ebx
    jmp .segment
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_tcp
; in:   rdi = "host port"
; out:  a connection opened and closed, and whether it worked
; clobbers: caller-saved
cmd_tcp:
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
    test eax, eax
    jz .usage
    cmp eax, 0xffff
    ja .usage
    mov r12d, eax
    mov rdi, rbx
    call net_resolve
    jc .refused
    mov edi, eax
    mov esi, r12d
    call tcp_connect
    jc .refused
    lea rdi, [rel tcp_msg_connected]
    call kputs
    mov edi, [rel tcp_peer]
    call net_put_ip
    mov edi, ':'
    call kputc
    mov edi, r12d
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    call tcp_close
    jmp .done
.refused:
    lea rdi, [rel tcp_msg_refused]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel tcp_msg_silent]
    cmp byte [rel tcp_peer_closed], 0
    je .print
    lea rdi, [rel tcp_msg_reset]
    jmp .print
.usage:
    lea rdi, [rel tcp_msg_usage]
    jmp .print
.no_net:
    lea rdi, [rel net_msg_none]
.print:
    call kputs
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

tcp_msg_connected db "[tcp] connected to ", 0
tcp_msg_refused   db "[tcp] no connection to ", 0
tcp_msg_usage     db "usage: tcp host port", 10, 0
tcp_msg_silent    db ": no answer", 10, 0
tcp_msg_reset     db ": reset", 10, 0

section .bss
alignb 8
tcp_packet      resb TCP_HDR + TCP_MSS
tcp_peer        resd 1
tcp_peer_port   resd 1
tcp_local_port  resd 1
tcp_snd_una     resd 1
tcp_snd_nxt     resd 1
tcp_rcv_nxt     resd 1
tcp_rx_len      resd 1
tcp_next_port   resw 1
tcp_state       resb 1
tcp_peer_closed resb 1
alignb 4096
tcp_rx          resb TCP_RX_SIZE
section .text
