; QEMU fw_cfg: reads the kernel command line from the file "opt/vitre/cmdline".
; Tests use it to select a scenario: -fw_cfg name=opt/vitre/cmdline,string=...

FWCFG_SEL   equ 0x510
FWCFG_DATA  equ 0x511
FWCFG_SIGNATURE equ 0x00
FWCFG_QEMU  equ 0x51454d55          ; "QEMU" read big-endian
FWCFG_DIR   equ 0x19
CMDLINE_MAX equ 255

; name: fwcfg_read_cmdline
; in:   none
; out:  kernel_cmdline holds the command line (empty if absent)
; clobbers: rax, rcx, rdx, rdi, rsi, r8
fwcfg_read_cmdline:
    mov byte [rel kernel_cmdline], 0
    ; without fw_cfg the data port floats to 0xff and the directory reads as 4G files
    mov dx, FWCFG_SEL
    mov ax, FWCFG_SIGNATURE
    out dx, ax
    call fwcfg_read_be32
    cmp eax, FWCFG_QEMU
    jne .done
    mov dx, FWCFG_SEL
    mov ax, FWCFG_DIR
    out dx, ax
    call fwcfg_read_be32
    mov r8d, eax                    ; file count
.entry:
    test r8d, r8d
    jz .done
    dec r8d
    call fwcfg_read_be32
    mov esi, eax                    ; size
    call fwcfg_read_be16
    mov ecx, eax                    ; selector
    call fwcfg_read_be16            ; reserved
    lea rdi, [rel fwcfg_name]
    push rcx
    mov ecx, 56
    mov dx, FWCFG_DATA
    rep insb
    pop rcx
    lea rdi, [rel fwcfg_name]
    lea rax, [rel fwcfg_cmdline_name]
    push rsi
    mov rsi, rax
    call str_eq
    pop rsi
    jne .entry

    mov dx, FWCFG_SEL
    mov eax, ecx
    out dx, ax
    mov ecx, esi
    cmp ecx, CMDLINE_MAX
    jbe .size_ok
    mov ecx, CMDLINE_MAX
.size_ok:
    lea rdi, [rel kernel_cmdline]
    mov dx, FWCFG_DATA
    rep insb
    mov byte [rdi], 0
.done:
    ret

; name: fwcfg_read_be32
; out:  eax = big-endian dword from the data port
; clobbers: rdx
fwcfg_read_be32:
    mov dx, FWCFG_DATA
    xor eax, eax
    in al, dx
    shl eax, 8
    in al, dx
    shl eax, 8
    in al, dx
    shl eax, 8
    in al, dx
    ret

; name: fwcfg_read_be16
; out:  eax = big-endian word from the data port
; clobbers: rdx
fwcfg_read_be16:
    mov dx, FWCFG_DATA
    xor eax, eax
    in al, dx
    shl eax, 8
    in al, dx
    ret

; name: cmdline_has
; in:   rdi = zero-terminated word
; out:  ZF=1 if the word appears in the kernel command line
; clobbers: rax, rcx, rdx, rsi
cmdline_has:
    lea rsi, [rel kernel_cmdline]
    jmp str_has_word

fwcfg_cmdline_name db "opt/vitre/cmdline", 0

section .bss
kernel_cmdline resb CMDLINE_MAX + 1
fwcfg_name     resb 57              ; 56-byte name field + terminator
section .text
