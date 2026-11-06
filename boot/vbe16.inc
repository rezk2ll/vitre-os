; name: vbe_set_mode
; in:   none
; out:  linear framebuffer mode set (1024x768x32, else 800x600x32), boot info
;       filled; CF=1 if neither mode exists
; clobbers: eax, ebx, ecx, edx, si, di, es, fs
vbe_set_mode:
    mov word [vbe_want_w], 1024
    mov word [vbe_want_h], 768
    call vbe_find_mode
    jnc .found
    mov word [vbe_want_w], 800
    mov word [vbe_want_h], 600
    call vbe_find_mode
    jc .done
.found:
    mov bx, cx
    or bx, 0x4000                   ; linear framebuffer
    mov ax, 0x4f02
    int 0x10
    cmp ax, 0x004f
    jne .fail
    mov eax, [VBE_MODE_BUF + 0x28]  ; PhysBasePtr
    mov [BOOTINFO_FB_ADDR], eax
    mov dword [BOOTINFO_FB_ADDR + 4], 0
    movzx eax, word [VBE_MODE_BUF + 0x10]   ; BytesPerScanLine
    cmp word [VBE_INFO_BUF + 0x04], 0x0300
    jb .pitch
    movzx eax, word [VBE_MODE_BUF + 0x32]   ; LinBytesPerScanLine, VBE 3.0
.pitch:
    mov [BOOTINFO_FB_PITCH], eax
    movzx eax, word [VBE_MODE_BUF + 0x12]
    mov [BOOTINFO_FB_WIDTH], eax
    movzx eax, word [VBE_MODE_BUF + 0x14]
    mov [BOOTINFO_FB_HEIGHT], eax
    movzx eax, byte [VBE_MODE_BUF + 0x19]
    mov [BOOTINFO_FB_BPP], eax
    clc
.done:
    ret
.fail:
    stc
    ret

; name: vbe_find_mode
; in:   vbe_want_w, vbe_want_h
; out:  cx = mode number with LFB and 32 bpp direct colour, mode info in
;       VBE_MODE_BUF; CF=1 if none
; clobbers: eax, ebx, ecx, edx, si, di, es, fs
vbe_find_mode:
    xor ax, ax
    mov es, ax
    mov di, VBE_INFO_BUF
    mov dword [di], 'VBE2'
    mov ax, 0x4f00
    int 0x10
    cmp ax, 0x004f
    jne .none
    mov si, [VBE_INFO_BUF + 0x0e]   ; mode list offset
    mov ax, [VBE_INFO_BUF + 0x10]   ; mode list segment
    mov fs, ax
.next:
    mov cx, [fs:si]
    add si, 2
    cmp cx, 0xffff
    je .none
    push si
    xor ax, ax
    mov es, ax
    mov di, VBE_MODE_BUF
    mov ax, 0x4f01
    int 0x10
    pop si
    cmp ax, 0x004f
    jne .next
    mov ax, [VBE_MODE_BUF]          ; attributes: supported + LFB
    and ax, 0x0081
    cmp ax, 0x0081
    jne .next
    cmp byte [VBE_MODE_BUF + 0x19], 32
    jne .next
    cmp byte [VBE_MODE_BUF + 0x1b], 6   ; direct colour
    jne .next
    mov ax, [vbe_want_w]
    cmp [VBE_MODE_BUF + 0x12], ax
    jne .next
    mov ax, [vbe_want_h]
    cmp [VBE_MODE_BUF + 0x14], ax
    jne .next
    clc
    ret
.none:
    stc
    ret

vbe_want_w dw 0
vbe_want_h dw 0
