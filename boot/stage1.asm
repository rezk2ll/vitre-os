; Stage 1: 512-byte MBR.
; M0 placeholder boot sector: prints a banner on COM1 and halts.
; STUB: does not load stage 2 yet (M1).

bits 16
org 0x7c00

COM1 equ 0x3f8

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7c00

    call serial_init
    mov si, msg_hello
    call serial_puts
.halt:
    hlt
    jmp .halt

; name: serial_init
; in:   none
; out:  COM1 at 115200 8N1, FIFO on
; clobbers: ax, dx
serial_init:
    mov dx, COM1 + 1
    xor al, al
    out dx, al              ; no interrupts
    mov dx, COM1 + 3
    mov al, 0x80
    out dx, al              ; DLAB on
    mov dx, COM1
    mov al, 1
    out dx, al              ; divisor 1 = 115200
    mov dx, COM1 + 1
    xor al, al
    out dx, al
    mov dx, COM1 + 3
    mov al, 3
    out dx, al              ; 8N1, DLAB off
    mov dx, COM1 + 2
    mov al, 0xc7
    out dx, al
    ret

; name: serial_puts
; in:   ds:si = zero-terminated string
; clobbers: ax, dx, si
serial_puts:
    lodsb
    test al, al
    jz .done
    mov ah, al
    mov dx, COM1 + 5
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov dx, COM1
    mov al, ah
    out dx, al
    jmp serial_puts
.done:
    ret

msg_hello db "[boot] stage1 ok", 13, 10, 0

times 510 - ($ - $$) db 0
dw 0xaa55
