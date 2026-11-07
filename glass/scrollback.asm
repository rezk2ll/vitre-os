; Scrollback for the kernel console. Every cell it draws is also kept in a
; ring of SB_LINES text lines, so lines that scrolled off the top can be
; drawn again. Screen row 0 is ring line sb_base; sb_view lines back from
; there is what the screen shows, 0 when it follows the output.

SB_LINES equ 512                    ; a power of two
SB_COLS  equ 128                    ; the widest console kept
SB_KEEP  equ SB_LINES - 64          ; history lines, leaving room for the screen

; name: sb_put
; in:   edx = character drawn at the kernel console's cursor
; out:  the cell stored with the console's foreground
; clobbers: rax, rcx, rdi
sb_put:
    mov rcx, [rel kernel_console + CON_CX]
    cmp rcx, SB_COLS
    jae .ret
    mov rax, [rel kernel_console + CON_CY]
    add eax, [rel sb_base]
    and eax, SB_LINES - 1
    shl eax, 7                      ; SB_COLS cells a line
    add eax, ecx
    mov ecx, [rel kernel_console + CON_FG]
    shl ecx, 8
    movzx edi, dl
    or ecx, edi
    lea rdi, [rel sb_ring]
    mov [rdi + rax * 4], ecx
.ret:
    ret

; name: sb_advance
; in:   edi = lines the screen moved up
; out:  those lines kept as history, the rows that came in blank
; clobbers: rax, rcx, rdx, rdi
sb_advance:
    test edi, edi
    jz .ret
    add [rel sb_base], edi
    add edi, [rel sb_hist]
    mov eax, SB_KEEP
    cmp edi, eax
    cmova edi, eax
    mov [rel sb_hist], edi
    mov edx, [rel kernel_console + CON_ROWS]
.blank:                             ; rows sb_base to sb_base + rows - 1
    dec edx
    js .ret
    mov eax, [rel sb_base]
    add eax, edx
    and eax, SB_LINES - 1
    shl eax, 9                      ; SB_COLS * 4 bytes a line
    lea rdi, [rel sb_ring]
    add rdi, rax
    xor eax, eax
    mov ecx, SB_COLS
    rep stosd
    jmp .blank
.ret:
    ret

; name: sb_clear
; in:   the kernel console about to be cleared
; out:  its used rows kept as history
; clobbers: rax, rcx, rdx, rdi
sb_clear:
    mov rdi, [rel kernel_console + CON_CY]
    cmp qword [rel kernel_console + CON_CX], 0
    je .advance
    inc rdi                         ; a partial last line counts
.advance:
    mov dword [rel sb_view], 0
    jmp sb_advance

; name: sb_scroll
; in:   edi = lines to go back, negative to come forward
; out:  sb_view moved within the history and the screen drawn from it
; clobbers: caller-saved
sb_scroll:
    mov eax, [rel sb_view]
    add eax, edi
    xor ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov ecx, [rel sb_hist]
    cmp eax, ecx
    cmova eax, ecx
    cmp eax, [rel sb_view]
    je .ret
    mov [rel sb_view], eax
    jmp sb_redraw
.ret:
    ret

; name: sb_live
; in:   none
; out:  the screen back on the newest lines if it was scrolled back
; clobbers: caller-saved
sb_live:
    cmp dword [rel sb_view], 0
    je .ret
    mov dword [rel sb_view], 0
    jmp sb_redraw
.ret:
    ret

; name: sb_redraw
; in:   sb_view
; out:  the kernel console's rows drawn from the ring
; clobbers: caller-saved
sb_redraw:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12d, r12d                  ; row
.row:
    cmp r12, [rel kernel_console + CON_ROWS]
    jae .done
    mov eax, [rel sb_base]
    sub eax, [rel sb_view]
    add eax, r12d
    and eax, SB_LINES - 1
    shl eax, 9
    lea r14, [rel sb_ring]
    add r14, rax
    xor r13d, r13d                  ; column
.cell:
    cmp r13, [rel kernel_console + CON_COLS]
    jae .next_row
    cmp r13, SB_COLS
    jae .next_row
    mov ebx, [r14 + r13 * 4]
    movzx edx, bl
    shr ebx, 8
    test edx, edx
    jnz .draw
    mov edx, ' '
    mov ebx, COLOR_FG
.draw:
    mov ecx, ebx
    mov r8d, [rel kernel_console + CON_BG]
    mov rdi, r13
    shl rdi, 3
    add rdi, [rel kernel_console + CON_X]
    mov rsi, r12
    shl rsi, 4
    add rsi, [rel kernel_console + CON_Y]
    call fb_draw_glyph
    inc r13
    jmp .cell
.next_row:
    inc r12
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: sb_getc
; in:   none (interrupts on)
; out:  eax = the next key; PgUp, PgDn and the wheel scroll the history
;       meanwhile, and any other key brings the newest lines back first
; clobbers: caller-saved
sb_getc:
    cmp byte [rel console_ready], 0
    je kbd_getc                     ; no screen to scroll
    push rbx
.wait:
    call kbd_poll
    jnz .key
    call mouse_scroll
    test eax, eax
    jz .sleep
    imul edi, eax, -3               ; three lines a notch, towards the user is forward
    call sb_scroll
    jmp .wait
.sleep:
    sti
    hlt                             ; any IRQ, the mouse's included, wakes it
    jmp .wait
.key:
    mov rdi, [rel kernel_console + CON_ROWS]
    dec edi                         ; a screen, keeping one line in view
    cmp eax, KEY_PGUP
    je .scroll
    neg edi
    cmp eax, KEY_PGDN
    je .scroll
    mov ebx, eax
    call sb_live
    mov eax, ebx
    pop rbx
    ret
.scroll:
    call sb_scroll
    jmp .wait

section .bss
alignb 4
sb_base resd 1
sb_hist resd 1                      ; lines above sb_base worth showing
sb_view resd 1
sb_ring resd SB_LINES * SB_COLS
section .text
