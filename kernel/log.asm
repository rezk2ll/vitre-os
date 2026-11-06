; Kernel log: every byte goes to COM1 (and to the console once it exists).

; name: kputc
; in:   dil = byte; '\n' is sent as "\r\n"
; out:  none
; clobbers: rax, rdx
kputc:
    cmp dil, 10
    jne .raw
    push rdi
    mov edi, 13
    call serial_putc
    pop rdi
.raw:
    jmp serial_putc

; name: kputs
; in:   rdi = zero-terminated string
; out:  none
; clobbers: rax, rdx, rdi
kputs:
    push rbx
    mov rbx, rdi
.next:
    movzx edi, byte [rbx]
    test dil, dil
    jz .done
    call kputc
    inc rbx
    jmp .next
.done:
    pop rbx
    ret

; name: kput_hex
; in:   rdi = value, printed as 16 hex digits
; out:  none
; clobbers: rax, rcx, rdx, rdi
kput_hex:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, 16
.digit:
    rol rbx, 4
    mov eax, ebx
    and eax, 15
    lea rdi, [rel hex_digits]
    movzx edi, byte [rdi + rax]
    call kputc
    dec r12d
    jnz .digit
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: kput_dec
; in:   rdi = unsigned value, printed in decimal
; out:  none
; clobbers: rax, rcx, rdx, rdi, rsi
kput_dec:
    sub rsp, 40
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rax, rdi
    mov ecx, 10
.div:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .div
    mov rdi, rsi
    call kputs
    add rsp, 40
    ret

hex_digits db "0123456789abcdef"
