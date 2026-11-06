; Kernel log: every byte goes to COM1 (and to the console once it exists).

; name: kputc
; in:   dil = byte; '\n' is sent as "\r\n" on serial
; out:  none
; clobbers: rax, rdx
kputc:
    push rdi
    cmp dil, 10
    jne .raw
    mov edi, 13
    call serial_putc
    mov rdi, [rsp]
.raw:
    call serial_putc
    pop rdi
    cmp byte [rel console_ready], 0
    je .done
    push rcx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    movzx esi, dil
    lea rdi, [rel kernel_console]
    call console_putc
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rcx
.done:
    ret

; name: klog_console_init
; in:   framebuffer initialised (fb_init)
; out:  kernel log also drawn on a full-screen console
; clobbers: caller-saved
klog_console_init:
    sub rsp, 8
    lea rdi, [rel kernel_console]
    xor esi, esi
    xor edx, edx
    mov rcx, [rel fb_width]
    shr rcx, 3
    mov r8, [rel fb_height]
    shr r8, 4
    call console_init
    mov byte [rel console_ready], 1
    add rsp, 8
    ret

section .bss
kernel_console resb CON_SIZE
console_ready  resb 1
section .text

; name: kputs
; in:   rdi = zero-terminated string
; out:  none; the string is written with interrupts off, so lines from
;       different tasks do not mix
; clobbers: rax, rdx, rdi
kputs:
    pushfq
    push rbx
    sub rsp, 8
    cli
    mov rbx, rdi
.next:
    movzx edi, byte [rbx]
    test dil, dil
    jz .done
    call kputc
    inc rbx
    jmp .next
.done:
    add rsp, 8
    pop rbx
    popfq
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

hex_digits db "0123456789abcdef"
