; Text console on a rectangle of the framebuffer, on the 8x16 character grid.
; A console is a struct, so Glass panes can each own one.

CON_X    equ 0                      ; pixel origin
CON_Y    equ 8
CON_COLS equ 16
CON_ROWS equ 24
CON_CX   equ 32                     ; cursor column
CON_CY   equ 40                     ; cursor row
CON_FG   equ 48
CON_BG   equ 56
CON_SIZE equ 64

COLOR_FG equ 0x00d8dee9
COLOR_BG equ 0x00101820

; name: console_init
; in:   rdi = console, rsi = x, rdx = y, rcx = cols, r8 = rows
; out:  console cleared with the default colours
; clobbers: caller-saved
console_init:
    mov [rdi + CON_X], rsi
    mov [rdi + CON_Y], rdx
    mov [rdi + CON_COLS], rcx
    mov [rdi + CON_ROWS], r8
    mov qword [rdi + CON_FG], COLOR_FG
    mov qword [rdi + CON_BG], COLOR_BG
    jmp console_clear

; name: console_clear
; in:   rdi = console
; out:  rectangle filled with the background, cursor at 0,0
; clobbers: caller-saved
console_clear:
    lea rax, [rel kernel_console]
    cmp rdi, rax
    jne .clear
    push rdi
    call sb_clear
    pop rdi
.clear:
    mov qword [rdi + CON_CX], 0
    mov qword [rdi + CON_CY], 0
    mov r8, [rdi + CON_BG]
    mov rdx, [rdi + CON_COLS]
    shl rdx, 3
    mov rcx, [rdi + CON_ROWS]
    shl rcx, 4
    mov rsi, [rdi + CON_Y]
    mov rdi, [rdi + CON_X]
    jmp fb_fill_rect

; name: console_putc
; in:   rdi = console, esi = character ('\n', '\r', '\b' handled)
; out:  none
; clobbers: caller-saved
console_putc:
    push rbx
    mov rbx, rdi
    cmp dword [rel sb_view], 0
    je .live
    lea rax, [rel kernel_console]
    cmp rbx, rax
    jne .live
    push rsi                        ; output brings the newest lines back
    push rsi
    call sb_live
    pop rsi
    pop rsi
.live:
    cmp esi, 10
    je .newline
    cmp esi, 13
    je .cr
    cmp esi, 8
    je .backspace
    call .draw
    inc qword [rbx + CON_CX]
    mov rax, [rbx + CON_CX]
    cmp rax, [rbx + CON_COLS]
    jb .done
.newline:
    mov qword [rbx + CON_CX], 0
    inc qword [rbx + CON_CY]
    mov rax, [rbx + CON_CY]
    cmp rax, [rbx + CON_ROWS]
    jb .done
    dec qword [rbx + CON_CY]
    mov rdi, rbx
    call console_scroll
    jmp .done
.cr:
    mov qword [rbx + CON_CX], 0
    jmp .done
.backspace:
    cmp qword [rbx + CON_CX], 0
    je .done
    dec qword [rbx + CON_CX]
    mov esi, ' '
    call .draw
.done:
    pop rbx
    ret
.draw:                              ; esi at the cursor of console rbx
    mov edx, esi
    lea rax, [rel kernel_console]
    cmp rbx, rax
    jne .glyph
    call sb_put
.glyph:
    mov rdi, [rbx + CON_CX]
    shl rdi, 3
    add rdi, [rbx + CON_X]
    mov rsi, [rbx + CON_CY]
    shl rsi, 4
    add rsi, [rbx + CON_Y]
    mov ecx, [rbx + CON_FG]
    mov r8d, [rbx + CON_BG]
    jmp fb_draw_glyph

; name: console_scroll
; in:   rdi = console
; out:  content moves up one text row, last row cleared
; clobbers: caller-saved
console_scroll:
    push rbx
    mov rbx, rdi
    lea rax, [rel kernel_console]
    cmp rbx, rax
    jne .move
    mov edi, 1
    call sb_advance
.move:
    mov rdi, [rbx + CON_X]
    mov rsi, [rbx + CON_Y]
    mov rdx, [rbx + CON_COLS]
    shl rdx, 3
    mov rcx, [rbx + CON_ROWS]
    shl rcx, 4
    mov r8d, FONT_HEIGHT
    call fb_scroll_rect
    mov rdi, [rbx + CON_X]
    mov rsi, [rbx + CON_ROWS]
    dec rsi
    shl rsi, 4
    add rsi, [rbx + CON_Y]
    mov rdx, [rbx + CON_COLS]
    shl rdx, 3
    mov ecx, FONT_HEIGHT
    mov r8, [rbx + CON_BG]
    call fb_fill_rect
    pop rbx
    ret

; name: console_puts
; in:   rdi = console, rsi = zero-terminated string
; out:  none
; clobbers: caller-saved
console_puts:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
.next:
    movzx esi, byte [r12]
    test esi, esi
    jz .done
    mov rdi, rbx
    call console_putc
    inc r12
    jmp .next
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
