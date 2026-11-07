; PCI configuration space through the legacy 0xcf8/0xcfc ports. A device is
; named by its config address: 0x80000000 | bus << 16 | device << 11 |
; function << 8.

PCI_ADDR   equ 0xcf8
PCI_DATA   equ 0xcfc
PCI_ENABLE equ 0x80000000

PCI_ID       equ 0x00               ; vendor in the low word, device in the high
PCI_COMMAND  equ 0x04
PCI_CLASS    equ 0x08               ; class, subclass, prog-if, revision from the top
PCI_HEADER   equ 0x0c               ; bit 23: multi-function device
PCI_BAR0     equ 0x10
PCI_IRQ_LINE equ 0x3c

PCI_CMD_MEMORY equ 2
PCI_CMD_MASTER equ 4

; name: pci_read
; in:   edi = device address, esi = register offset (dword aligned)
; out:  eax = the register
; clobbers: rax, rdx
pci_read:
    lea eax, [rdi + rsi]
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    ret

; name: pci_next
; in:   edi = device address to start from (PCI_ENABLE for the first)
; out:  eax = address of the first present function at or after it; CF=1
;       once every bus has been scanned
; clobbers: rax, rdx, rdi, rsi
pci_next:
.probe:
    test edi, 0x700
    jz .function
    push rdi                        ; functions 1-7 exist only on multi-function devices
    and edi, ~0x700
    mov esi, PCI_HEADER
    call pci_read
    pop rdi
    test eax, 1 << 23
    jnz .function
    or edi, 0x700
    jmp .advance
.function:
    xor esi, esi
    call pci_read
    cmp ax, 0xffff
    jne .found
.advance:
    add edi, 0x100
    test edi, 0x01000000            ; carried out of the bus number
    jz .probe
    stc
    ret
.found:
    mov eax, edi
    clc
    ret

; name: pci_write
; in:   edi = device address, esi = register offset, edx = value
; out:  the register written
; clobbers: rax, rdx
pci_write:
    lea eax, [rdi + rsi]
    push rdx
    mov dx, PCI_ADDR
    out dx, eax
    pop rax
    mov dx, PCI_DATA
    out dx, eax
    ret

; name: pci_find
; in:   edi = vendor << 16 | device id, as in "8086:100e"
; out:  eax = address of the first such device; CF=1 if there is none
; clobbers: rax, rcx, rdx, rdi, rsi
pci_find:
    rol edi, 16                     ; PCI_ID holds the vendor in the low word
    mov ecx, edi
    mov edi, PCI_ENABLE
.next:
    call pci_next
    jc .done
    mov edi, eax
    xor esi, esi
    call pci_read
    cmp eax, ecx
    je .match
    add edi, 0x100
    jmp .next
.match:
    mov eax, edi
    clc
.done:
    ret

; name: cmd_lspci
; in:   rdi = arguments (ignored)
; out:  one line per function: "bb:dd.f vvvv:dddd class cc.ss irq n"
; clobbers: caller-saved
cmd_lspci:
    push rbx
    mov ebx, PCI_ENABLE
.next:
    mov edi, ebx
    call pci_next
    jc .done
    mov ebx, eax
    mov edi, ebx
    shr edi, 16
    mov esi, 2
    call kput_hexn
    mov edi, ':'
    call kputc
    mov edi, ebx
    shr edi, 11
    and edi, 31
    mov esi, 2
    call kput_hexn
    mov edi, '.'
    call kputc
    mov edi, ebx
    shr edi, 8
    and edi, 7
    mov esi, 1
    call kput_hexn
    mov edi, ' '
    call kputc
    mov edi, ebx
    xor esi, esi
    call pci_read
    push rax
    sub rsp, 8
    mov edi, eax
    mov esi, 4
    call kput_hexn
    mov edi, ':'
    call kputc
    add rsp, 8
    pop rdi
    shr edi, 16
    mov esi, 4
    call kput_hexn
    lea rdi, [rel pci_msg_class]
    call kputs
    mov edi, ebx
    mov esi, PCI_CLASS
    call pci_read
    push rax
    sub rsp, 8
    mov edi, eax
    shr edi, 24
    mov esi, 2
    call kput_hexn
    mov edi, '.'
    call kputc
    add rsp, 8
    pop rdi
    shr edi, 16
    mov esi, 2
    call kput_hexn
    lea rdi, [rel pci_msg_irq]
    call kputs
    mov edi, ebx
    mov esi, PCI_IRQ_LINE
    call pci_read
    movzx edi, al
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    add ebx, 0x100
    jmp .next
.done:
    pop rbx
    ret

pci_msg_class db " class ", 0
pci_msg_irq   db " irq ", 0
