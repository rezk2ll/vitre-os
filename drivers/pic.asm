; 8259 PIC pair, remapped to vectors 32-47.

PIC1_CMD  equ 0x20
PIC1_DATA equ 0x21
PIC2_CMD  equ 0xa0
PIC2_DATA equ 0xa1
IRQ_BASE  equ 32

; name: pic_init
; in:   none
; out:  IRQ 0-15 on vectors 32-47, everything masked except the cascade
; clobbers: rax
pic_init:
    mov al, 0x11                    ; ICW1: init, expect ICW4
    out PIC1_CMD, al
    out PIC2_CMD, al
    mov al, IRQ_BASE
    out PIC1_DATA, al
    mov al, IRQ_BASE + 8
    out PIC2_DATA, al
    mov al, 4                       ; slave on IRQ 2
    out PIC1_DATA, al
    mov al, 2
    out PIC2_DATA, al
    mov al, 1                       ; 8086 mode
    out PIC1_DATA, al
    out PIC2_DATA, al
    mov al, 0xfb
    out PIC1_DATA, al
    mov al, 0xff
    out PIC2_DATA, al
    ret

; name: pic_unmask
; in:   rdi = irq (0-15)
; out:  none
; clobbers: rax, rcx, rdx
pic_unmask:
    mov ecx, edi
    mov dx, PIC1_DATA
    cmp ecx, 8
    jb .port
    mov dx, PIC2_DATA
    sub ecx, 8
.port:
    in al, dx
    mov ah, 1
    shl ah, cl
    not ah
    and al, ah
    out dx, al
    ret

; name: pic_eoi
; in:   rdi = irq (0-15)
; out:  none
; clobbers: rax
pic_eoi:
    mov al, 0x20
    cmp edi, 8
    jb .master
    out PIC2_CMD, al
.master:
    out PIC1_CMD, al
    ret
