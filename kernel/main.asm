; Kernel image, loaded by stage 2 at KERNEL_PHYS and entered in long mode
; with paging identity-mapping the first 4 GiB.

%include "boot/layout.inc"

bits 64
org KERNEL_PHYS

kernel_entry:
    mov rsp, KERNEL_STACK_TOP
    lea rdi, [rel msg_long_mode]
    call serial_puts
    ; the last qword of the image proves stage 2 loaded all of it
    mov rax, KERNEL_END_MAGIC
    cmp [rel kernel_end_magic], rax
    lea rdi, [rel msg_image_ok]
    je .image_ok
    lea rdi, [rel msg_image_bad]
.image_ok:
    call serial_puts
.halt:
    cli
    hlt
    jmp .halt

%include "drivers/serial.asm"

msg_long_mode db "[boot] long mode ok", 13, 10, 0
msg_image_ok  db "[kernel] image ok", 13, 10, 0
msg_image_bad db "[kernel] image truncated", 13, 10, 0

KERNEL_END_MAGIC equ 0x444e454552544956       ; "VITREEND"
align 8
kernel_end_magic dq KERNEL_END_MAGIC
