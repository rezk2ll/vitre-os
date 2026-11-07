; PS/2 keyboard on IRQ 1, scancode set 1 (the i8042 translates by default).
; Key codes: ASCII for printable keys, Enter = 10, Backspace = 8, Tab = 9,
; Ctrl+letter = 1-26, KEY_* in 0x80-0x9f for keys without a character, and
; Latin-1 (0xa0-0xff) for accented and other non-ASCII characters.

KEY_UP    equ 0x80
KEY_DOWN  equ 0x81
KEY_LEFT  equ 0x82
KEY_RIGHT equ 0x83
KEY_PGUP  equ 0x84
KEY_PGDN  equ 0x85
KEY_HOME  equ 0x86
KEY_END   equ 0x87
KEY_DEL   equ 0x88
KEY_F1    equ 0x90                  ; F1-F10 are 0x90-0x99
KEY_ESC   equ 27

KBD_BUF_SIZE equ 64                 ; power of two

; name: kbd_init
; in:   kernel command line read
; out:  layout chosen, IRQ 1 handler installed and unmasked
; clobbers: caller-saved
kbd_init:
    sub rsp, 8
    lea rdi, [rel kbd_opt_qwerty]
    call cmdline_has
    jnz .drain
    mov byte [rel kbd_layout], KBD_LAYOUT_QWERTY
.drain:
    in al, 0x64                     ; drop bytes left from the BIOS
    test al, 1
    jz .empty
    in al, 0x60
    jmp .drain
.empty:
    mov edi, IRQ_BASE + 1
    lea rsi, [rel kbd_irq]
    call isr_set_handler
    mov edi, 1
    call pic_unmask
    add rsp, 8
    ret

; name: kbd_irq
; in:   rdi = frame
; out:  rax = frame
; clobbers: caller-saved
kbd_irq:
    push rdi
    in al, 0x64
    test al, 0x20                   ; the mouse's byte: IRQ 12 takes it
    jnz .eoi
    in al, 0x60
    movzx edi, al
    call kbd_scancode
.eoi:
    mov edi, 1
    call pic_eoi
    pop rax
    ret

; name: kbd_scancode
; in:   edi = set 1 scancode byte
; out:  key code queued if the byte completes a key press
; clobbers: rax, rcx, rdx
kbd_scancode:
    cmp edi, 0xe0
    je .prefix
    movzx ecx, byte [rel kbd_e0]
    mov byte [rel kbd_e0], 0
    mov eax, edi
    and eax, 0x7f                   ; make code
    test edi, 0x80
    jnz .release

    cmp eax, 0x1d
    je .ctrl_down
    ; E0 2A / E0 36 are fake shifts around extended keys: they fall into
    ; .extended and are ignored there
    test ecx, ecx
    jnz .extended
    mov dl, 1
    cmp eax, 0x2a
    je .shift_down
    mov dl, 2
    cmp eax, 0x36
    je .shift_down
    cmp eax, 0x3b                   ; F1-F10
    jb .ascii
    cmp eax, 0x44
    ja .iso_key
    add eax, KEY_F1 - 0x3b
    jmp kbd_push
.iso_key:
    cmp eax, 0x56                   ; the extra key left of Z on ISO boards
    jne .ignore
    mov eax, KBD_MAP_ISO
    jmp .lookup
.ascii:
    cmp eax, 0x3a                   ; caps lock
    je .ignore
.lookup:
    movzx edx, byte [rel kbd_layout]
    imul edx, 3
    cmp byte [rel kbd_altgr], 0
    je .no_altgr
    add edx, 2
    jmp .map
.no_altgr:
    cmp byte [rel kbd_shift], 0
    je .map
    inc edx
.map:
    imul edx, KBD_MAP_SIZE
    lea rcx, [rel kbd_maps]
    add rdx, rcx
    movzx eax, byte [rdx + rax]
    test eax, eax
    jz .ignore
    cmp byte [rel kbd_ctrl], 0
    je kbd_push
    or eax, 0x20                    ; lowercase, so Ctrl+Shift+letter maps too
    cmp eax, 'a'
    jb .ignore
    cmp eax, 'z'
    ja .ignore
    sub eax, 'a' - 1
    jmp kbd_push

.extended:
    cmp eax, 0x38                   ; E0 38 is AltGr
    je .altgr_down
    lea rdx, [rel kbd_ext_codes]
.ext_next:
    movzx ecx, byte [rdx]
    test ecx, ecx
    jz .ignore
    cmp ecx, eax
    je .ext_found
    add rdx, 2
    jmp .ext_next
.ext_found:
    movzx eax, byte [rdx + 1]
    jmp kbd_push

.release:
    cmp eax, 0x1d
    je .ctrl_up
    test ecx, ecx
    jz .plain_release
    cmp eax, 0x38
    jne .ignore
    mov byte [rel kbd_altgr], 0
    ret
.plain_release:
    mov dl, 1
    cmp eax, 0x2a
    je .shift_up
    mov dl, 2
    cmp eax, 0x36
    je .shift_up
    ret
; kbd_shift and kbd_ctrl hold one bit per physical key, so releasing one of
; two held keys keeps the modifier
.shift_down:
    or [rel kbd_shift], dl
    ret
.shift_up:
    not dl
    and [rel kbd_shift], dl
    ret
.ctrl_down:
    mov dl, 1                       ; bit 0 left, bit 1 right (E0 1D)
    shl dl, cl
    or [rel kbd_ctrl], dl
    ret
.ctrl_up:
    mov dl, 1
    shl dl, cl
    not dl
    and [rel kbd_ctrl], dl
    ret
.altgr_down:
    mov byte [rel kbd_altgr], 1
    ret
.prefix:
    mov byte [rel kbd_e0], 1
.ignore:
    ret

; name: kbd_push
; in:   eax = key code
; out:  queued, dropped if the buffer is full
; clobbers: rcx, rdx
kbd_push:
    mov ecx, [rel kbd_head]
    mov edx, ecx
    inc edx
    and edx, KBD_BUF_SIZE - 1
    cmp edx, [rel kbd_tail]
    je .full
    lea rdx, [rel kbd_buf]
    mov [rdx + rcx], al
    inc ecx
    and ecx, KBD_BUF_SIZE - 1
    mov [rel kbd_head], ecx
.full:
    ret

; name: kbd_poll
; in:   none
; out:  eax = key code, ZF=1 and eax = 0 if no key is waiting
; clobbers: rcx, rdx
kbd_poll:
    cli
    xor eax, eax
    mov ecx, [rel kbd_tail]
    cmp ecx, [rel kbd_head]
    je .done
    lea rdx, [rel kbd_buf]
    movzx eax, byte [rdx + rcx]
    inc ecx
    and ecx, KBD_BUF_SIZE - 1
    mov [rel kbd_tail], ecx
    test eax, eax
.done:
    sti
    ret

; name: kbd_getc
; in:   none (interrupts on)
; out:  eax = next key code, waits for one
; clobbers: rcx, rdx
kbd_getc:
    cli
    mov ecx, [rel kbd_tail]
    cmp ecx, [rel kbd_head]
    jne kbd_poll
    sti                             ; sti; hlt cannot lose an IRQ in between
    hlt
    jmp kbd_getc

; Layout maps, indexed by scancode 0x00-0x39 plus KBD_MAP_ISO for scancode
; 0x56. Each layout has a plain, a Shift and an AltGr map, in that order.
; Bytes from 0xa0 are Latin-1 characters, written as numbers because the
; source file is UTF-8.
KBD_LAYOUT_AZERTY equ 0
KBD_LAYOUT_QWERTY equ 1
KBD_MAP_ISO  equ 0x3a
KBD_MAP_SIZE equ 0x3b

kbd_maps:
    ; AZERTY (French)
    db 0, KEY_ESC, "&", 0xe9, '"', "'(-", 0xe8, "_", 0xe7, 0xe0, ")=", 8, 9
    db "azertyuiop^$", 10, 0, "qs"
    db "dfghjklm", 0xf9, 0xb2, 0, "*wxcv"
    db "bn,;:!", 0, "*", 0, " ", "<"
    db 0, KEY_ESC, "1234567890", 0xb0, "+", 8, 9
    db "AZERTYUIOP", 0xa8, 0xa3, 10, 0, "QS"
    db "DFGHJKLM%", 0, 0, 0xb5, "WXCV"
    db "BN?./", 0xa7, 0, "*", 0, " ", ">"
    db 0, 0, 0, "~#{[|`\^@]}", 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xa4, 0, 0, 0, 0
    times 16 db 0
    times 11 db 0
    ; QWERTY (US)
    db 0, KEY_ESC, "1234567890-=", 8, 9
    db "qwertyuiop[]", 10, 0, "as"
    db "dfghjkl;'`", 0, "\zxcv"
    db "bnm,./", 0, "*", 0, " ", "\"
    db 0, KEY_ESC, "!@#$%^&*()_+", 8, 9
    db "QWERTYUIOP{}", 10, 0, "AS"
    db "DFGHJKL:", '"', "~", 0, "|ZXCV"
    db "BNM<>?", 0, "*", 0, " ", "|"
    times KBD_MAP_SIZE db 0
kbd_maps_end:
; division by zero (an assembly error) unless every map has KBD_MAP_SIZE bytes
KBD_MAPS_CHECK equ 1 / ((kbd_maps_end - kbd_maps) == 6 * KBD_MAP_SIZE)

kbd_opt_qwerty db "kbd=qwerty", 0

; extended (E0) make codes and their key codes
kbd_ext_codes:
    db 0x48, KEY_UP, 0x50, KEY_DOWN, 0x4b, KEY_LEFT, 0x4d, KEY_RIGHT
    db 0x49, KEY_PGUP, 0x51, KEY_PGDN, 0x47, KEY_HOME, 0x4f, KEY_END
    db 0x53, KEY_DEL, 0x1c, 10, 0

section .bss
kbd_buf   resb KBD_BUF_SIZE
kbd_head  resd 1
kbd_tail  resd 1
kbd_shift resb 1
kbd_ctrl  resb 1
kbd_e0    resb 1
kbd_altgr resb 1
kbd_layout resb 1                   ; KBD_LAYOUT_*, AZERTY unless kbd=qwerty
section .text
