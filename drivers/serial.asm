; COM1 serial output. Stage 1 already programmed the UART (115200 8N1).

SERIAL_COM1 equ 0x3f8

; name: serial_putc
; in:   dil = byte
; out:  none
; clobbers: rax, rdx
serial_putc:
    mov dx, SERIAL_COM1 + 5
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov dx, SERIAL_COM1
    mov al, dil
    out dx, al
    ret
