; Linear framebuffer set up by stage 2 (32 bpp, 0x00RRGGBB).

; name: fb_init
; in:   boot info filled by stage 2
; out:  fb_* variables set, CF=1 if no framebuffer
; clobbers: rax
fb_init:
    mov rax, [BOOTINFO_FB_ADDR]
    test rax, rax
    jz .none
    mov [rel fb_base], rax
    mov eax, [BOOTINFO_FB_PITCH]
    mov [rel fb_pitch], rax
    mov eax, [BOOTINFO_FB_WIDTH]
    mov [rel fb_width], rax
    mov eax, [BOOTINFO_FB_HEIGHT]
    mov [rel fb_height], rax
    clc
    ret
.none:
    stc
    ret

; name: fb_fill_rect
; in:   rdi = x, rsi = y, rdx = width, rcx = height, r8d = colour
; out:  none
; clobbers: rax, rcx, rdx, rdi, rsi, r9, r10
fb_fill_rect:
    mov r9, rdx
    mov r10, rcx
    mov rax, [rel fb_pitch]
    imul rsi, rax
    lea rsi, [rsi + rdi * 4]
    add rsi, [rel fb_base]
    mov eax, r8d
.row:
    test r10, r10
    jz .done
    mov rdi, rsi
    mov rcx, r9
    rep stosd
    add rsi, [rel fb_pitch]
    dec r10
    jmp .row
.done:
    ret

; name: fb_draw_glyph
; in:   rdi = x, rsi = y, edx = character, ecx = foreground, r8d = background
; out:  none; characters outside the font draw as '?'
; clobbers: rax, rcx, rdx, rdi, rsi, r9, r10, r11
fb_draw_glyph:
    sub edx, FONT_FIRST
    cmp edx, FONT_LAST - FONT_FIRST
    jbe .known
    mov edx, '?' - FONT_FIRST
.known:
    shl edx, 4
    lea r9, [rel font_8x16]
    add r9, rdx                     ; glyph rows
    mov rax, [rel fb_pitch]
    imul rsi, rax
    lea rdi, [rsi + rdi * 4]
    add rdi, [rel fb_base]
    mov r10d, FONT_HEIGHT
.row:
    movzx r11d, byte [r9]
    mov edx, 8
    mov rsi, rdi
.px:
    mov eax, r8d
    shl r11b, 1
    cmovc eax, ecx
    mov [rsi], eax
    add rsi, 4
    dec edx
    jnz .px
    inc r9
    add rdi, [rel fb_pitch]
    dec r10d
    jnz .row
    ret

; name: fb_scroll_rect
; in:   rdi = x, rsi = y, rdx = width, rcx = height, r8 = lines to move up
; out:  the rectangle's content moves up by r8 pixel lines; the bottom r8
;       lines keep their old content (callers clear them)
; clobbers: rax, rcx, rdx, rdi, rsi, r9, r10, r11
fb_scroll_rect:
    mov r9, rdx
    mov r10, rcx
    sub r10, r8                     ; rows to copy
    mov rax, [rel fb_pitch]
    imul rsi, rax
    lea rdi, [rsi + rdi * 4]
    add rdi, [rel fb_base]          ; destination row
    mov r11, r8
    imul r11, rax
    add r11, rdi                    ; source row
.row:
    test r10, r10
    jz .done
    push rdi
    mov rsi, r11
    mov rcx, r9
    rep movsd
    pop rdi
    add rdi, [rel fb_pitch]
    add r11, [rel fb_pitch]
    dec r10
    jmp .row
.done:
    ret

section .bss
fb_base   resq 1
fb_pitch  resq 1
fb_width  resq 1
fb_height resq 1
section .text
