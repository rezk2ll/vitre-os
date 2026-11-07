; Intel 82540EM (e1000) as QEMU emulates it: one receive and one transmit
; descriptor ring in identity-mapped memory, received frames handed to
; eth_input from the IRQ handler.

E1000_ID      equ 0x8086100e

E1000_CTRL    equ 0x0000
E1000_STATUS  equ 0x0008
E1000_ICR     equ 0x00c0
E1000_IMS     equ 0x00d0
E1000_IMC     equ 0x00d8
E1000_RCTL    equ 0x0100
E1000_TCTL    equ 0x0400
E1000_TIPG    equ 0x0410
E1000_RDBAL   equ 0x2800
E1000_RDBAH   equ 0x2804
E1000_RDLEN   equ 0x2808
E1000_RDH     equ 0x2810
E1000_RDT     equ 0x2818
E1000_TDBAL   equ 0x3800
E1000_TDBAH   equ 0x3804
E1000_TDLEN   equ 0x3808
E1000_TDH     equ 0x3810
E1000_TDT     equ 0x3818
E1000_MTA     equ 0x5200
E1000_RAL     equ 0x5400
E1000_RAH     equ 0x5404

E1000_CTRL_SLU   equ 1 << 6
E1000_CTRL_RST   equ 1 << 26
E1000_STATUS_LU  equ 1 << 1
E1000_RCTL_EN    equ 1 << 1
E1000_RCTL_BAM   equ 1 << 15        ; accept broadcast
E1000_RCTL_SECRC equ 1 << 26        ; strip the CRC
E1000_TCTL_EN    equ 1 << 1
E1000_TCTL_PSP   equ 1 << 3
E1000_TCTL_CT    equ 0x10 << 4
E1000_TCTL_COLD  equ 0x40 << 12
E1000_TIPG_VALUE equ 0x0060200a
E1000_INT_RXT0   equ 1 << 7
E1000_INT_RXO    equ 1 << 6

E1000_DESC     equ 16
E1000_D_ADDR   equ 0
E1000_D_LEN    equ 8
E1000_D_CMD    equ 11               ; transmit
E1000_D_STATUS equ 12
E1000_DD       equ 1                ; descriptor done
E1000_CMD_EOP  equ 1
E1000_CMD_IFCS equ 2
E1000_CMD_RS   equ 8

E1000_RX_COUNT equ 32
E1000_TX_COUNT equ 8
E1000_BUF      equ 2048
ETH_FRAME_MAX  equ 1514

; name: e1000_init
; in:   none
; out:  the card reset, rings armed and its IRQ unmasked; logs the MAC.
;       CF=1 if there is no e1000 or no pages for the rings
; clobbers: caller-saved
e1000_init:
    push rbx
    push r12
    sub rsp, 8
    mov edi, E1000_ID
    call pci_find
    jc .absent
    mov r12d, eax
    mov edi, r12d
    mov esi, PCI_COMMAND
    call pci_read
    or eax, PCI_CMD_MEMORY | PCI_CMD_MASTER
    mov edx, eax
    mov edi, r12d
    mov esi, PCI_COMMAND
    call pci_write
    mov edi, r12d
    mov esi, PCI_BAR0
    call pci_read
    and eax, ~0xf
    mov ebx, eax
    mov [rel e1000_mmio], rbx
    mov edi, r12d
    mov esi, PCI_IRQ_LINE
    call pci_read
    movzx eax, al
    mov [rel e1000_irq], eax

    mov dword [rbx + E1000_IMC], 0xffffffff
    or dword [rbx + E1000_CTRL], E1000_CTRL_RST
.reset:
    pause
    test dword [rbx + E1000_CTRL], E1000_CTRL_RST
    jnz .reset
    mov eax, [rbx + E1000_ICR]
    or dword [rbx + E1000_CTRL], E1000_CTRL_SLU
    xor ecx, ecx
.mta:
    mov dword [rbx + E1000_MTA + rcx * 4], 0
    inc ecx
    cmp ecx, 128
    jb .mta
    mov eax, [rbx + E1000_RAL]      ; QEMU loads the MAC here at reset
    mov [rel net_mac], eax
    mov eax, [rbx + E1000_RAH]
    mov [rel net_mac + 4], ax
    or dword [rbx + E1000_RAH], 1 << 31     ; address valid

    mov edi, 1 + (E1000_RX_COUNT + E1000_TX_COUNT) * E1000_BUF / PAGE_SIZE
    call page_alloc
    jc .absent
    mov [rel e1000_rx_ring], rax    ; one page: rx ring, then tx ring
    lea rcx, [rax + E1000_RX_COUNT * E1000_DESC]
    mov [rel e1000_tx_ring], rcx
    lea rdx, [rax + PAGE_SIZE]      ; buffers follow
    mov rdi, rax
    push rdi
    mov ecx, PAGE_SIZE / 8
    xor eax, eax
    rep stosq
    pop rdi
    xor ecx, ecx
.rx_desc:
    mov [rdi + E1000_D_ADDR], rdx
    add rdx, E1000_BUF
    add rdi, E1000_DESC
    inc ecx
    cmp ecx, E1000_RX_COUNT
    jb .rx_desc
    xor ecx, ecx
.tx_desc:
    mov [rdi + E1000_D_ADDR], rdx
    mov byte [rdi + E1000_D_STATUS], E1000_DD   ; free
    add rdx, E1000_BUF
    add rdi, E1000_DESC
    inc ecx
    cmp ecx, E1000_TX_COUNT
    jb .tx_desc

    mov rax, [rel e1000_rx_ring]
    mov [rbx + E1000_RDBAL], eax
    shr rax, 32
    mov [rbx + E1000_RDBAH], eax
    mov dword [rbx + E1000_RDLEN], E1000_RX_COUNT * E1000_DESC
    mov dword [rbx + E1000_RDH], 0
    mov dword [rbx + E1000_RDT], E1000_RX_COUNT - 1
    mov rax, [rel e1000_tx_ring]
    mov [rbx + E1000_TDBAL], eax
    shr rax, 32
    mov [rbx + E1000_TDBAH], eax
    mov dword [rbx + E1000_TDLEN], E1000_TX_COUNT * E1000_DESC
    mov dword [rbx + E1000_TDH], 0
    mov dword [rbx + E1000_TDT], 0
    mov dword [rbx + E1000_TIPG], E1000_TIPG_VALUE
    mov dword [rbx + E1000_TCTL], E1000_TCTL_EN | E1000_TCTL_PSP | E1000_TCTL_CT | E1000_TCTL_COLD
    mov dword [rbx + E1000_RCTL], E1000_RCTL_EN | E1000_RCTL_BAM | E1000_RCTL_SECRC

    mov edi, [rel e1000_irq]
    add edi, IRQ_BASE
    lea rsi, [rel e1000_isr]
    call isr_set_handler
    mov edi, [rel e1000_irq]
    call pic_unmask
    mov dword [rbx + E1000_IMS], E1000_INT_RXT0 | E1000_INT_RXO
    mov byte [rel net_ready], 1
    lea rdi, [rel e1000_msg_up]
    call kputs
    call net_put_mac
    lea rdi, [rel e1000_msg_irq]
    call kputs
    mov edi, [rel e1000_irq]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    clc
    jmp .done
.absent:
    stc
.done:
    lea rsp, [rsp + 8]              ; keeps CF
    pop r12
    pop rbx
    ret

; name: e1000_isr
; in:   rdi = frame
; out:  rax = frame; every completed receive descriptor handed to eth_input
;       and given back to the card
; clobbers: caller-saved
e1000_isr:
    push rbx
    push r12
    push rdi
    mov rbx, [rel e1000_mmio]
    mov eax, [rbx + E1000_ICR]      ; reading acknowledges
.next:
    mov r12d, [rel e1000_rx_next]
    mov rax, r12
    shl rax, 4
    add rax, [rel e1000_rx_ring]
    test byte [rax + E1000_D_STATUS], E1000_DD
    jz .eoi
    inc qword [rel net_rx_frames]
    push rax
    sub rsp, 8
    movzx esi, word [rax + E1000_D_LEN]
    mov rdi, [rax + E1000_D_ADDR]
    call eth_input
    add rsp, 8
    pop rax
    mov byte [rax + E1000_D_STATUS], 0
    mov [rbx + E1000_RDT], r12d     ; this descriptor is the card's again
    inc r12d
    and r12d, E1000_RX_COUNT - 1
    mov [rel e1000_rx_next], r12d
    jmp .next
.eoi:
    mov edi, [rel e1000_irq]
    call pic_eoi
    pop rax
    pop r12
    pop rbx
    ret

; name: e1000_send
; in:   rdi = frame, esi = length (at most ETH_FRAME_MAX)
; out:  the frame queued for transmission; CF=1 if no descriptor came free
; clobbers: caller-saved
e1000_send:
    push rbx
    pushfq                          ; the IRQ path sends too (ARP replies)
    cli
    mov rbx, [rel e1000_mmio]
    mov ecx, [rel e1000_tx_next]
    mov rdx, rcx
    shl rdx, 4
    add rdx, [rel e1000_tx_ring]
    mov r8d, 1000000
.wait:
    test byte [rdx + E1000_D_STATUS], E1000_DD
    jnz .free
    pause
    dec r8d
    jnz .wait
    popfq
    pop rbx
    stc
    ret
.free:
    mov r8, rdi
    mov rdi, [rdx + E1000_D_ADDR]
    mov r9d, ecx
    mov ecx, esi
    mov r10, rsi
    mov rsi, r8
    rep movsb
    mov [rdx + E1000_D_LEN], r10w
    mov byte [rdx + E1000_D_CMD], E1000_CMD_EOP | E1000_CMD_IFCS | E1000_CMD_RS
    mov byte [rdx + E1000_D_STATUS], 0
    inc r9d
    and r9d, E1000_TX_COUNT - 1
    mov [rel e1000_tx_next], r9d
    mov [rbx + E1000_TDT], r9d
    inc qword [rel net_tx_frames]
    popfq
    pop rbx
    clc
    ret

; name: e1000_link_up
; in:   none
; out:  ZF=0 if the link is up
; clobbers: rax
e1000_link_up:
    mov rax, [rel e1000_mmio]
    test dword [rax + E1000_STATUS], E1000_STATUS_LU
    ret

e1000_msg_up  db "[net] e1000 mac ", 0
e1000_msg_irq db " irq ", 0

section .bss
alignb 8
e1000_mmio    resq 1
e1000_rx_ring resq 1
e1000_tx_ring resq 1
e1000_irq     resd 1
e1000_rx_next resd 1
e1000_tx_next resd 1
section .text
