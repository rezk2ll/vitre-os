; ICMP echo: answers pings, and `ping` sends them.

ICMP_TYPE       equ 0
ICMP_CODE       equ 1
ICMP_SUM        equ 2
ICMP_ID         equ 4
ICMP_SEQ        equ 6
ICMP_HDR        equ 8
ICMP_ECHO_REPLY equ 0
ICMP_ECHO       equ 8

PING_ID       equ 0x5649            ; "VI"
PING_DATA     equ 32
PING_COUNT    equ 4
PING_WAIT_MS  equ 1000

; name: icmp_input
; in:   rdi = ICMP message, esi = length, edx = sender
; out:  echo requests answered; the reply to our current ping recorded
; clobbers: caller-saved
icmp_input:
    cmp esi, ICMP_HDR
    jb .drop
    cmp esi, IP_MTU - IP_HDR
    ja .drop
    call net_checksum
    test ax, ax                     ; a valid message sums to zero
    jnz .drop
    mov al, [rdi + ICMP_TYPE]
    cmp al, ICMP_ECHO
    je .request
    cmp al, ICMP_ECHO_REPLY
    jne .drop
    cmp word [rdi + ICMP_ID], (PING_ID >> 8) | ((PING_ID & 0xff) << 8)
    jne .drop
    cmp edx, [rel ping_target]
    jne .drop
    movzx eax, word [rdi + ICMP_SEQ]
    xchg al, ah
    mov [rel ping_seen], eax
.drop:
    ret
.request:
    push rbx                        ; reply with the same id, sequence and data
    push r12
    push r13
    mov ebx, edx
    mov r12d, esi
    mov rsi, rdi
    lea rdi, [rel icmp_reply]
    mov r13, rdi
    mov ecx, r12d
    rep movsb
    mov byte [r13 + ICMP_TYPE], ICMP_ECHO_REPLY
    mov word [r13 + ICMP_SUM], 0
    mov rdi, r13
    mov esi, r12d
    call net_checksum
    mov [r13 + ICMP_SUM], ax
    mov edi, ebx
    mov esi, IP_PROTO_ICMP
    mov rdx, r13
    mov ecx, r12d
    call ip_send
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_ping
; in:   rdi = "a.b.c.d"
; out:  PING_COUNT echo requests, one line per reply or timeout, then a
;       summary
; clobbers: caller-saved
cmd_ping:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp byte [rel net_ready], 0
    je .no_net
    call net_parse_ip
    jc .usage
    mov [rel ping_target], eax
    mov dword [rel ping_seen], 0
    xor ebx, ebx                    ; sequence
    xor r15d, r15d                  ; replies
.send:
    inc ebx
    lea r12, [rel ping_packet]
    mov byte [r12 + ICMP_TYPE], ICMP_ECHO
    mov byte [r12 + ICMP_CODE], 0
    mov word [r12 + ICMP_SUM], 0
    mov word [r12 + ICMP_ID], (PING_ID >> 8) | ((PING_ID & 0xff) << 8)
    mov eax, ebx
    xchg al, ah
    mov [r12 + ICMP_SEQ], ax
    lea rdi, [r12 + ICMP_HDR]
    mov ecx, PING_DATA
    mov al, 'a'
.fill:
    stosb
    inc al
    loop .fill
    mov rdi, r12
    mov esi, ICMP_HDR + PING_DATA
    call net_checksum
    mov [r12 + ICMP_SUM], ax
    mov r13, [rel timer_ticks]
    mov edi, [rel ping_target]
    mov esi, IP_PROTO_ICMP
    mov rdx, r12
    mov ecx, ICMP_HDR + PING_DATA
    call ip_send
    jc .unreachable
    lea r14, [r13 + PING_WAIT_MS]
.wait:
    cmp [rel ping_seen], ebx
    je .reply
    call task_yield
    cmp [rel timer_ticks], r14
    jb .wait
    lea rdi, [rel ping_msg_timeout]
    call kputs
    mov edi, ebx
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    jmp .next
.reply:
    inc r15d
    lea rdi, [rel ping_msg_reply]
    call kputs
    mov edi, [rel ping_target]
    call net_put_ip
    lea rdi, [rel ping_msg_seq]
    call kputs
    mov edi, ebx
    call [rel jt_kput_dec]
    lea rdi, [rel ping_msg_time]
    call kputs
    mov rdi, [rel timer_ticks]
    sub rdi, r13
    call [rel jt_kput_dec]
    lea rdi, [rel ping_msg_ms]
    call kputs
.pace:                              ; one request per second
    call task_yield
    cmp [rel timer_ticks], r14
    jb .pace
.next:
    cmp ebx, PING_COUNT
    jb .send
    lea rdi, [rel ping_msg_sent]
    call kputs
    mov edi, PING_COUNT
    call [rel jt_kput_dec]
    lea rdi, [rel ping_msg_received]
    call kputs
    mov edi, r15d
    call [rel jt_kput_dec]
    lea rdi, [rel ping_msg_end]
    call kputs
    jmp .done
.unreachable:
    lea rdi, [rel ping_msg_unreachable]
    call kputs
    jmp .done
.usage:
    lea rdi, [rel ping_msg_usage]
    call kputs
    jmp .done
.no_net:
    lea rdi, [rel net_msg_none]
    call kputs
.done:
    mov dword [rel ping_target], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ping_msg_reply       db "[ping] reply from ", 0
ping_msg_seq         db " seq ", 0
ping_msg_time        db " time ", 0
ping_msg_ms          db " ms", 10, 0
ping_msg_timeout     db "[ping] no reply, seq ", 0
ping_msg_sent        db "[ping] ", 0
ping_msg_received    db " sent, ", 0
ping_msg_end         db " received", 10, 0
ping_msg_unreachable db "[ping] no route: the next hop did not answer ARP", 10, 0
ping_msg_usage       db "usage: ping a.b.c.d", 10, 0

section .bss
alignb 8
icmp_reply  resb IP_MTU - IP_HDR
ping_packet resb ICMP_HDR + PING_DATA
ping_target resd 1
ping_seen   resd 1
section .text
