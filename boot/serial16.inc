; Real-mode COM1 output shared by stage 1 and stage 2.

COM1 equ 0x3f8

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
