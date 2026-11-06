; Stage 1: 512-byte MBR.
; Sets up COM1, loads stage 2 with int 13h extended reads and jumps to it
; with dl = boot drive.

%include "boot/layout.inc"

bits 16
org 0x7c00

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    jmp 0:.flat             ; some BIOSes enter at 07c0:0000
.flat:
    sti
    mov [boot_drive], dl

    call serial_init
    mov si, msg_hello
    call serial_puts

    mov ah, 0x41            ; extended reads supported?
    mov bx, 0x55aa
    mov dl, [boot_drive]
    int 0x13
    jc .no_ext
    cmp bx, 0xaa55
    jne .no_ext
    test cx, 1              ; DAP (ah=42h) subset
    jz .no_ext

    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc .disk_error

    mov dl, [boot_drive]
    jmp 0:STAGE2_ADDR

.no_ext:
    mov si, msg_no_ext
    jmp .fail
.disk_error:
    mov si, msg_disk
.fail:
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

%include "boot/serial16.inc"

align 4
dap:
    db 0x10, 0
    dw STAGE2_SECTORS
    dw STAGE2_ADDR, 0
    dq STAGE2_LBA

boot_drive db 0

msg_hello  db "[boot] stage1 ok", 13, 10, 0
msg_no_ext db "[boot] no int13 extensions", 13, 10, 0
msg_disk   db "[boot] stage2 read failed", 13, 10, 0

times 510 - ($ - $$) db 0
dw 0xaa55
