; 8253/8254 PIT channel 0 at 1000 Hz, counting ticks.

PIT_HZ      equ 1000
PIT_DIVISOR equ 1193182 / PIT_HZ

; name: pit_init
; in:   none
; out:  IRQ 0 handler installed and unmasked
; clobbers: rax, rcx, rdx, rdi, rsi
pit_init:
    mov al, 0x34                    ; channel 0, lo/hi, mode 2
    out 0x43, al
    mov al, PIT_DIVISOR & 0xff
    out 0x40, al
    mov al, PIT_DIVISOR >> 8
    out 0x40, al
    mov edi, IRQ_BASE + 0
    lea rsi, [rel pit_irq]
    call isr_set_handler
    xor edi, edi
    call pic_unmask
    ret

; name: pit_irq
; in:   rdi = frame
; out:  rax = frame
; clobbers: caller-saved
pit_irq:
    inc qword [rel timer_ticks]
    push rdi
    xor edi, edi
    call pic_eoi
    pop rax
    ret

; name: timer_sleep_ms
; in:   rdi = milliseconds (interrupts must be on)
; out:  none
; clobbers: rax, rdi
timer_sleep_ms:
    mov rax, [rel timer_ticks]
    add rdi, rax
.wait:
    hlt
    cmp [rel timer_ticks], rdi
    jb .wait
    ret

section .bss
timer_ticks resq 1
section .text
