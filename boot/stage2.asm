; Stage 2: real mode -> long mode.
; Loaded by stage 1 at 0x8000, entered with dl = boot drive.

%include "boot/layout.inc"

bits 16
org STAGE2_ADDR

stage2_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti                     ; BIOS disk services may wait on IRQs
    mov [boot_drive], dl

    mov si, msg_stage2
    call serial_puts

    call long_mode_check
    jc fail_cpu
    call a20_enable
    jc fail_a20
    call e820_read
    call kernel_load
    jc fail_disk

    mov si, msg_kernel
    call serial_puts

    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp GDT_CODE32:pm_entry

fail_cpu:
    mov si, msg_cpu
    jmp fail
fail_a20:
    mov si, msg_a20
    jmp fail
fail_disk:
    mov si, msg_disk
fail:
    call serial_puts
.halt:
    hlt
    jmp .halt

%include "boot/serial16.inc"

; name: long_mode_check
; out:  CF=1 if the CPU has no long mode
; clobbers: eax, ebx, ecx, edx
long_mode_check:
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no
    mov eax, 0x80000001
    cpuid
    bt edx, 29
    cmc
    ret
.no:
    stc
    ret

; name: a20_enable
; out:  CF=1 if A20 could not be enabled
; clobbers: ax, cx, si, di, es, fs
a20_enable:
    call a20_check
    jnc .ok
    mov ax, 0x2401          ; BIOS method
    int 0x15
    call a20_check
    jnc .ok
    in al, 0x92             ; fast A20
    or al, 2
    and al, 0xfe
    out 0x92, al
    call a20_check
.ok:
    ret

; name: a20_check
; out:  CF=0 if A20 is on (0x0000:0x0500 and 0xffff:0x0510 differ)
; clobbers: ax, si, di, es, fs
a20_check:
    xor ax, ax
    mov fs, ax
    not ax
    mov es, ax
    mov di, 0x0510
    mov si, 0x0500
    mov al, [fs:si]
    push ax
    mov byte [fs:si], 0x00
    mov byte [es:di], 0xff
    cmp byte [fs:si], 0xff
    pop ax
    mov [fs:si], al
    clc
    jne .on
    stc
.on:
    ret

; name: e820_read
; out:  boot info e820 count and entries filled
; clobbers: eax, ebx, ecx, edx, bp, di, es
e820_read:
    xor ax, ax
    mov es, ax
    mov di, BOOTINFO_E820
    xor ebx, ebx
    xor bp, bp
.next:
    mov eax, 0xe820
    mov edx, 0x534d4150     ; 'SMAP'
    mov ecx, 24
    mov dword [es:di + 20], 1
    int 0x15
    jc .done
    cmp eax, 0x534d4150
    jne .done
    test ecx, ecx
    jz .skip
    inc bp
    add di, 24
    cmp bp, BOOTINFO_E820_MAX
    jae .done
.skip:
    test ebx, ebx
    jnz .next
.done:
    mov [BOOTINFO_E820_COUNT], bp
    ret

; name: kernel_load
; in:   boot_drive
; out:  KERNEL_SECTORS sectors from KERNEL_LBA copied to KERNEL_PHYS, CF=1 on error
; clobbers: eax, ebx, ecx, edx, esi, edi
kernel_load:
    mov dword [load_lba], KERNEL_LBA
    mov dword [load_dst], KERNEL_PHYS
    mov word [load_left], KERNEL_SECTORS
.loop:
    mov ax, [load_left]
    test ax, ax
    jz .done
    cmp ax, LOAD_CHUNK
    jbe .count_ok
    mov ax, LOAD_CHUNK
.count_ok:
    mov [dap_count], ax
    mov word [dap_off], 0
    mov word [dap_seg], LOAD_BUF >> 4
    mov eax, [load_lba]
    mov [dap_lba], eax
    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc .error

    call unreal_enter
    movzx ecx, word [dap_count]
    shl ecx, 7              ; sectors -> dwords
    mov esi, LOAD_BUF
    mov edi, [load_dst]
    a32 rep movsd

    movzx eax, word [dap_count]
    add [load_lba], eax
    sub [load_left], ax
    shl eax, 9
    add [load_dst], eax
    jmp .loop
.done:
    clc
    ret
.error:
    stc
    ret

; name: unreal_enter
; out:  ds and es keep their real-mode base with a 4 GiB cached limit
; clobbers: eax
unreal_enter:
    pushf
    cli
    push ds
    push es
    lgdt [gdt_desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp $ + 2
    mov ax, GDT_DATA
    mov ds, ax
    mov es, ax
    mov eax, cr0
    and al, 0xfe
    mov cr0, eax
    pop es
    pop ds
    popf
    ret

bits 32
pm_entry:
    mov ax, GDT_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x7c00

    ; identity map the first 4 GiB with 2 MiB pages
    mov edi, PAGING_BASE
    mov ecx, (PAGING_SIZE) / 4
    xor eax, eax
    rep stosd

    mov dword [PML4_ADDR], PDPT_ADDR | 3
    mov edi, PDPT_ADDR
    mov eax, PD_ADDR | 3
    mov ecx, 4
.pdpt:
    mov [edi], eax
    add eax, 0x1000
    add edi, 8
    loop .pdpt

    mov edi, PD_ADDR
    mov eax, 0x83           ; present, writable, 2 MiB
    xor edx, edx
    mov ecx, 2048
.pd:
    mov [edi], eax
    mov [edi + 4], edx
    add eax, 0x200000
    adc edx, 0
    add edi, 8
    loop .pd

    mov eax, cr4
    or eax, 1 << 5          ; PAE
    mov cr4, eax
    mov eax, PML4_ADDR
    mov cr3, eax
    mov ecx, 0xc0000080     ; EFER
    rdmsr
    or eax, 1 << 8          ; LME
    wrmsr
    mov eax, cr0
    or eax, 1 << 31         ; paging
    mov cr0, eax
    jmp GDT_CODE64:lm_entry

bits 64
lm_entry:
    xor eax, eax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov rsp, KERNEL_STACK_TOP
    mov rax, KERNEL_PHYS
    jmp rax

align 8
gdt:
    dq 0
    dq 0x00cf9a000000ffff   ; 0x08 code32
    dq 0x00cf92000000ffff   ; 0x10 data
    dq 0x00209a0000000000   ; 0x18 code64
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt

GDT_CODE32 equ 0x08
GDT_DATA   equ 0x10
GDT_CODE64 equ 0x18

align 4
dap:
    db 0x10, 0
dap_count dw 0
dap_off   dw 0
dap_seg   dw 0
dap_lba   dq 0

load_lba  dd 0
load_dst  dd 0
load_left dw 0
boot_drive db 0

msg_stage2 db "[boot] stage2", 13, 10, 0
msg_kernel db "[boot] kernel loaded", 13, 10, 0
msg_cpu    db "[boot] CPU has no long mode", 13, 10, 0
msg_a20    db "[boot] A20 failed", 13, 10, 0
msg_disk   db "[boot] disk read failed", 13, 10, 0

times STAGE2_SECTORS * 512 - ($ - $$) db 0     ; negative = stage 2 too large
