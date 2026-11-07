; AC'97 audio (Intel 82801AA) as QEMU emulates it: 48 kHz, 16-bit stereo
; through the PCM out channel. Buffers are queued on its ring of 32
; descriptors; the card plays them in turn and stops after the last one.

AC97_ID        equ 0x80862415
AC97_RATE      equ 48000
AC97_FRAMES    equ 32767            ; a descriptor counts 16-bit samples
AC97_RING      equ 32

AC97_RESET     equ 0x00             ; mixer, at BAR0
AC97_MASTER    equ 0x02
AC97_PCM_VOL   equ 0x18
AC97_PO_BDBAR  equ 0x10             ; bus master, at BAR1: PCM out
AC97_PO_CIV    equ 0x14
AC97_PO_LVI    equ 0x15
AC97_PO_SR     equ 0x16
AC97_PO_CR     equ 0x1b
AC97_GLOB_CNT  equ 0x2c
AC97_GLOB_STA  equ 0x30

AC97_CR_RUN    equ 1
AC97_CR_RESET  equ 2
AC97_SR_HALTED equ 1
AC97_COLD      equ 2                ; GLOB_CNT: out of cold reset
AC97_CODEC_UP  equ 1 << 8           ; GLOB_STA: primary codec ready
AC97_0DB       equ 0x0808

; name: ac97_init
; in:   none
; out:  the card out of reset, volumes up and the ring empty; logs it.
;       CF=1 if there is no AC'97 card or no page for the ring
; clobbers: caller-saved
ac97_init:
    push rbx
    mov edi, AC97_ID
    call pci_find
    jc .ret
    mov ebx, eax
    mov edi, ebx
    mov esi, PCI_COMMAND
    call pci_read
    or eax, PCI_CMD_IO | PCI_CMD_MASTER
    mov edx, eax
    mov edi, ebx
    mov esi, PCI_COMMAND
    call pci_write
    mov edi, ebx
    mov esi, PCI_BAR0
    call pci_read
    and eax, 0xfffc
    mov [rel ac97_nam], ax
    mov edi, ebx
    mov esi, PCI_BAR0 + 4
    call pci_read
    and eax, 0xfffc
    mov [rel ac97_nabm], ax
    movzx edx, word [rel ac97_nabm]
    add edx, AC97_GLOB_CNT
    mov eax, AC97_COLD
    out dx, eax
    mov ecx, 100000
.codec:
    movzx edx, word [rel ac97_nabm]
    add edx, AC97_GLOB_STA
    in eax, dx
    test eax, AC97_CODEC_UP
    jnz .up
    dec ecx
    jnz .codec
    stc
    jmp .ret
.up:
    movzx edx, word [rel ac97_nam]
    xor eax, eax
    out dx, ax                      ; any write resets the mixer
    add edx, AC97_MASTER
    out dx, ax                      ; 0: loudest, not muted
    add edx, AC97_PCM_VOL - AC97_MASTER
    mov eax, AC97_0DB
    out dx, ax
    mov edi, 1
    call page_alloc
    jc .ret
    mov [rel ac97_ring], rax
    call ac97_stop
    mov byte [rel ac97_ready], 1
    lea rdi, [rel ac97_msg_ready]
    call kputs
    clc
.ret:
    pop rbx
    ret

; name: ac97_queue
; in:   rdi = samples: 16-bit left then right, 48 kHz; esi = frames, at
;       most AC97_FRAMES. The buffer must stay until it has played.
; out:  it plays after the buffers queued before it; CF=1 if there is no
;       card or the ring is full
; clobbers: rax, rcx, rdx, rsi
ac97_queue:
    cmp byte [rel ac97_ready], 0
    je .no
    movzx edx, word [rel ac97_nabm]
    add edx, AC97_PO_CIV
    in al, dx
    movzx ecx, byte [rel ac97_tail]
    sub ecx, eax
    and ecx, AC97_RING - 1
    cmp ecx, AC97_RING - 2
    jae .no
    movzx ecx, byte [rel ac97_tail]
    mov rax, [rel ac97_ring]
    lea rax, [rax + rcx * 8]
    mov [rax], edi
    add esi, esi
    mov [rax + 4], esi              ; samples, and no flags
    movzx edx, word [rel ac97_nabm]
    add edx, AC97_PO_LVI
    mov eax, ecx
    out dx, al                      ; a halted card goes on from here
    inc ecx
    and ecx, AC97_RING - 1
    mov [rel ac97_tail], cl
    add edx, AC97_PO_CR - AC97_PO_LVI
    in al, dx
    test al, AC97_CR_RUN
    jnz .queued                     ; setting it again skips to the next buffer
    mov al, AC97_CR_RUN
    out dx, al
.queued:
    clc
    ret
.no:
    stc
    ret

; name: ac97_busy
; in:   none
; out:  CF=1 while a queued buffer is still playing
; clobbers: rax, rdx
ac97_busy:
    cmp byte [rel ac97_ready], 0
    je .idle
    movzx edx, word [rel ac97_nabm]
    add edx, AC97_PO_SR
    in ax, dx
    test eax, AC97_SR_HALTED
    jnz .idle
    stc
    ret
.idle:
    clc
    ret

; name: ac97_stop
; in:   none
; out:  playing stopped and the ring emptied; nothing without a card
; clobbers: rax, rdx
ac97_stop:
    cmp qword [rel ac97_ring], 0
    je .ret
    movzx edx, word [rel ac97_nabm]
    add edx, AC97_PO_CR
    mov al, AC97_CR_RESET
    out dx, al
.wait:
    in al, dx
    test al, AC97_CR_RESET
    jnz .wait
    mov byte [rel ac97_tail], 0
    add edx, AC97_PO_BDBAR - AC97_PO_CR ; the reset forgets the ring
    mov eax, [rel ac97_ring]
    out dx, eax
.ret:
    ret

ac97_msg_ready db "[sound] ac97 ready", 10, 0

section .bss
alignb 8
ac97_ring  resq 1
ac97_nam   resw 1
ac97_nabm  resw 1
ac97_tail  resb 1
ac97_ready resb 1
section .text
