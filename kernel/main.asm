; Kernel image, loaded by stage 2 at KERNEL_PHYS and entered in long mode
; with paging identity-mapping the first 4 GiB.
;
; Code and data live in .text. Zero-initialised state goes in .bss, which
; the bin format places after the image; kernel_entry clears it.

%include "boot/layout.inc"

bits 64
org KERNEL_PHYS
section .text
section .bss nobits align=16
bss_start:
section .text

kernel_entry:
    mov rsp, KERNEL_STACK_TOP
    cld
    mov rdi, bss_start
    mov rcx, bss_end
    sub rcx, rdi
    xor eax, eax
    rep stosb

    call fb_init
    jc .headless
    call klog_console_init
.headless:
    lea rdi, [rel msg_long_mode]
    call kputs
    cmp byte [rel console_ready], 0
    je .no_fb
    call fb_log_mode
.no_fb:
    ; the last qword of the image proves stage 2 loaded all of it
    mov rax, KERNEL_END_MAGIC
    cmp [rel kernel_end_magic], rax
    lea rdi, [rel msg_image_ok]
    je .image_ok
    lea rdi, [rel msg_image_bad]
.image_ok:
    call kputs

    call fwcfg_read_cmdline
    lea rdi, [rel msg_cmdline]
    call kputs
    lea rdi, [rel kernel_cmdline]
    call kputs
    mov edi, 10
    call kputc

    call pmm_init
    call pmm_log
    call idt_init
    call pic_init
    call pit_init
    call kbd_init
    sti
    lea rdi, [rel msg_interrupts]
    call kputs

    call kernel_selftests
    lea rdi, [rel msg_echo]
    call kputs
.echo:
    call kbd_getc
    cmp eax, 0x80
    jae .echo
    mov edi, eax
    call kputc
    jmp .echo

; name: kernel_selftests
; in:   none
; out:  runs the scenarios named on the command line (test=...)
; clobbers: caller-saved
kernel_selftests:
    sub rsp, 8
    lea rdi, [rel test_pit]
    call cmdline_has
    jnz .no_pit
    call selftest_pit
.no_pit:
    lea rdi, [rel test_ud]
    call cmdline_has
    jnz .no_ud
    ud2
.no_ud:
    add rsp, 8
    ret

; name: selftest_pit
; in:   none
; out:  logs the tick count three times, 100 ms apart
; clobbers: caller-saved
selftest_pit:
    push rbx
    mov ebx, 3
.again:
    mov edi, 100
    call timer_sleep_ms
    lea rdi, [rel msg_ticks]
    call kputs
    mov rdi, [rel timer_ticks]
    call kput_dec
    mov edi, 10
    call kputc
    dec ebx
    jnz .again
    pop rbx
    ret

%include "drivers/serial.asm"
%include "kernel/log.asm"
%include "kernel/idt.asm"
%include "kernel/exception.asm"
%include "drivers/pic.asm"
%include "drivers/pit.asm"
%include "drivers/fwcfg.asm"
%include "lib/string.asm"
%include "drivers/fb.asm"
%include "glass/font.asm"
%include "glass/console.asm"
%include "drivers/keyboard.asm"
%include "kernel/pmm.asm"
%include "kernel/heap.asm"

msg_long_mode  db "[boot] long mode ok", 10, 0
msg_image_ok   db "[kernel] image ok", 10, 0
msg_image_bad  db "[kernel] image truncated", 10, 0
msg_cmdline    db "[kernel] cmdline: ", 0
msg_interrupts db "[kernel] interrupts on", 10, 0
msg_echo       db "[kbd] echo ready", 10, 0
msg_ticks      db "[timer] ticks=", 0
test_pit       db "test=pit", 0
test_ud        db "test=ud", 0
KERNEL_END_MAGIC equ 0x444e454552544956       ; "VITREEND"
align 8
kernel_end_magic dq KERNEL_END_MAGIC

section .bss
bss_end:
