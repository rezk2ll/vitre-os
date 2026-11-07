; Desktop: `desktop` takes the screen and shows a launcher, a tile per app
; under a bar with the clock. The tile under the pointer is outlined; a
; click on a tile, or its number, opens the app; the desktop comes back
; when it ends. q or Esc return to the shell.

DT_BAR_H    equ 24
DT_TILE_W   equ 200
DT_TILE_H   equ 140
DT_GAP      equ 40
DT_COLS     equ 4
DT_TILES    equ 8
DT_ENTRY    equ 32                  ; label, action, argument, colour, letter
DT_SCALE    equ 4                   ; icon letters are the font at 4x
DT_OUTLINE  equ 3                   ; the hovered tile's border, in pixels
DT_NONE     equ 0xff
DT_BAR_BG   equ 0x000f141e
DT_TEXT     equ 0x00eceff4
DT_DIM      equ 0x009aa5b8

%macro dt_tile 6                    ; label, length, action, argument, colour, letter
    dq %1, %3, %4
    dd %5
    db %6, %2, 0, 0
%endmacro

; name: cmd_desktop
; in:   rdi = arguments (ignored)
; out:  the desktop ran until q, Esc or the Terminal tile; screen cleared
; clobbers: caller-saved
cmd_desktop:
    push rbx
    push r12
    cmp byte [rel console_ready], 0
    je .no_screen
.redraw:
    call dt_draw
    call mouse_click                ; forget clicks made in the app
    mov byte [rel dt_hover], DT_NONE
    mov r12, [rel timer_ticks]
.loop:
    call kbd_poll
    jnz .key
    call mouse_click
    jc .hover
    call dt_hit
    jnc .launch
.hover:
    call dt_hover_update
.tick:
    mov rax, [rel timer_ticks]
    sub rax, r12
    cmp rax, 1000
    jb .idle
    call dt_clock
    mov r12, [rel timer_ticks]
.idle:
    call task_yield
    jmp .loop
.key:
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    sub eax, '1'
    cmp eax, DT_TILES
    jae .loop
.launch:
    imul eax, eax, DT_ENTRY
    lea rbx, [rel dt_tiles]
    add rbx, rax
    mov rax, [rbx + 8]
    test rax, rax
    jz .quit                        ; Terminal: back to the shell
    call shell_clear_screen
    mov rdi, [rbx + 16]
    call [rbx + 8]
    jmp .redraw
.quit:
    call shell_clear_screen
    jmp .done
.no_screen:
    lea rdi, [rel br_msg_no_screen]
    call kputs
.done:
    pop r12
    pop rbx
    ret

; name: dt_draw
; in:   none
; out:  the whole desktop drawn
; clobbers: caller-saved
dt_draw:
    push rbx
    push r12
    mov ebx, DT_BAR_H               ; the background, a gradient by row
.row:
    cmp rbx, [rel fb_height]
    jae .bar
    mov rax, rbx
    imul rax, rax, 0x30
    xor edx, edx
    div qword [rel fb_height]
    lea r8d, [rax + 0x18]
    shl r8d, 8
    mov rax, rbx
    imul rax, rax, 0x40
    xor edx, edx
    div qword [rel fb_height]
    lea r8d, [r8 + rax + 0x24]
    shl r8d, 8
    mov rax, rbx
    imul rax, rax, 0x60
    xor edx, edx
    div qword [rel fb_height]
    lea r8d, [r8 + rax + 0x3c]
    xor edi, edi
    mov rsi, rbx
    mov rdx, [rel fb_width]
    mov ecx, 1
    call fb_fill_rect
    inc ebx
    jmp .row
.bar:
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov ecx, DT_BAR_H
    mov r8d, DT_BAR_BG
    call fb_fill_rect
    mov edi, 12
    mov esi, 4
    lea rdx, [rel dt_msg_name]
    mov ecx, DT_TEXT
    mov r8d, DT_BAR_BG
    call dt_text
    xor ebx, ebx
.tile:
    mov edi, ebx
    call dt_tile_draw
    inc ebx
    cmp ebx, DT_TILES
    jb .tile
    mov rdi, [rel fb_width]         ; the hint, centred in the bar
    sub rdi, dt_msg_hint_len * 8
    shr rdi, 1
    mov esi, 4
    lea rdx, [rel dt_msg_hint]
    mov ecx, DT_DIM
    mov r8d, DT_BAR_BG
    call dt_text
    call dt_clock
    pop r12
    pop rbx
    ret

; name: dt_origin
; in:   edi = tile index
; out:  rax = its left edge, rdx = its top edge
; clobbers: rax, rcx, rdx
dt_origin:
    mov eax, edi
    xor edx, edx
    mov ecx, DT_COLS
    div ecx                         ; eax = row, edx = column
    push rax
    imul edx, edx, DT_TILE_W + DT_GAP
    mov rax, [rel fb_width]
    sub rax, DT_COLS * DT_TILE_W + (DT_COLS - 1) * DT_GAP
    shr rax, 1
    add rax, rdx
    pop rdx
    imul edx, edx, DT_TILE_H + DT_GAP
    mov rcx, [rel fb_height]
    sub rcx, 2 * DT_TILE_H + DT_GAP
    shr rcx, 1
    add rdx, rcx
    ret

; name: dt_tile_draw
; in:   edi = tile index
; out:  the tile drawn: a box in its colour, its letter large, its label
; clobbers: caller-saved
dt_tile_draw:
    push rbx
    push r12
    push r13
    imul eax, edi, DT_ENTRY
    lea rbx, [rel dt_tiles]
    add rbx, rax
    call dt_origin
    mov r12, rax
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    mov edx, DT_TILE_W
    mov ecx, DT_TILE_H
    mov r8d, [rbx + 24]
    call fb_fill_rect
    lea rdi, [r12 + (DT_TILE_W - 8 * DT_SCALE) / 2]
    lea rsi, [r13 + 16]
    movzx edx, byte [rbx + 28]
    mov ecx, DT_TEXT
    call dt_big
    movzx eax, byte [rbx + 29]      ; the label, centred at the bottom
    lea rdi, [r12 + DT_TILE_W / 2]
    shl eax, 2
    sub rdi, rax
    lea rsi, [r13 + DT_TILE_H - 28]
    mov rdx, [rbx]
    mov ecx, DT_TEXT
    mov r8d, [rbx + 24]
    call dt_text
    pop r13
    pop r12
    pop rbx
    ret

; name: dt_big
; in:   rdi = x, rsi = y, edx = character, ecx = colour
; out:  the character drawn DT_SCALE times its size, background untouched
; clobbers: caller-saved
dt_big:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r15d, ecx
    sub edx, FONT_FIRST
    shl edx, 4
    lea rbx, [rel font_8x16]
    add rbx, rdx
    xor r14d, r14d                  ; r14 = row << 8 | column
.px:
    mov eax, r14d
    shr eax, 8
    movzx edx, byte [rbx + rax]
    mov ecx, r14d
    and ecx, 7
    shl edx, cl
    test dl, 0x80
    jz .next
    mov edi, r14d
    and edi, 7
    imul edi, edi, DT_SCALE
    add rdi, r12
    imul esi, eax, DT_SCALE
    add rsi, r13
    mov edx, DT_SCALE
    mov ecx, DT_SCALE
    mov r8d, r15d
    call fb_fill_rect
.next:
    inc r14d
    test r14d, 8
    jz .px
    add r14d, 256 - 8               ; the next row, column 0
    cmp r14d, 16 << 8
    jb .px
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: dt_text
; in:   rdi = x, rsi = y, rdx = string, ecx = foreground, r8d = background
; out:  the string drawn on one line
; clobbers: caller-saved
dt_text:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov r14d, ecx
    mov r15d, r8d
.char:
    movzx edx, byte [rbx]
    test edx, edx
    jz .done
    mov rdi, r12
    mov rsi, r13
    mov ecx, r14d
    mov r8d, r15d
    call fb_draw_glyph
    add r12, 8
    inc rbx
    jmp .char
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: dt_clock
; in:   none
; out:  the date and time drawn at the right of the bar
; clobbers: caller-saved
dt_clock:
    call rtc_read
    lea rsi, [rel rtc_now]
    lea rdi, [rel dt_clock_text]
    lea rdx, [rel dt_clock_layout]
.copy:
    mov al, [rdx]
    inc rdx
    cmp al, '#'
    jne .put
    mov al, [rsi]
    inc rsi
.put:
    stosb
    test al, al
    jnz .copy
    mov rdi, [rel fb_width]
    sub rdi, dt_clock_len * 8 + 12
    mov esi, 4
    lea rdx, [rel dt_clock_text]
    mov ecx, DT_DIM
    mov r8d, DT_BAR_BG
    jmp dt_text

; name: dt_hit
; in:   mouse_x, mouse_y
; out:  eax = the tile under the pointer; CF=1 if none
; clobbers: rax, rcx, rdx, rdi
dt_hit:
    xor edi, edi
.tile:
    call dt_origin
    mov ecx, [rel mouse_x]
    sub rcx, rax
    cmp rcx, DT_TILE_W              ; unsigned: left of it wraps around
    jae .next
    mov ecx, [rel mouse_y]
    sub rcx, rdx
    cmp rcx, DT_TILE_H
    jae .next
    mov eax, edi
    clc
    ret
.next:
    inc edi
    cmp edi, DT_TILES
    jb .tile
    stc
    ret

; name: dt_hover_update
; in:   none
; out:  the tile under the pointer outlined, the one before drawn plain
; clobbers: caller-saved
dt_hover_update:
    push rbx
    mov ebx, DT_NONE
    cmp qword [rel mouse_moves], 0
    je .got                         ; no pointer on the screen yet
    call dt_hit
    jc .got
    mov ebx, eax
.got:
    movzx edi, byte [rel dt_hover]
    cmp edi, ebx
    je .ret
    mov [rel dt_hover], bl
    cmp edi, DT_NONE
    je .outline
    call dt_tile_draw
.outline:
    cmp ebx, DT_NONE
    je .ret
    mov edi, ebx
    call dt_outline
.ret:
    pop rbx
    ret

; name: dt_outline
; in:   edi = tile index
; out:  a light border drawn just inside the tile
; clobbers: caller-saved
dt_outline:
    push r12
    push r13
    sub rsp, 8
    call dt_origin
    mov r12, rax
    mov r13, rdx
    mov rdi, r12                    ; top
    mov rsi, r13
    mov edx, DT_TILE_W
    mov ecx, DT_OUTLINE
    mov r8d, DT_TEXT
    call fb_fill_rect
    mov rdi, r12                    ; bottom
    lea rsi, [r13 + DT_TILE_H - DT_OUTLINE]
    mov edx, DT_TILE_W
    mov ecx, DT_OUTLINE
    mov r8d, DT_TEXT
    call fb_fill_rect
    mov rdi, r12                    ; left
    mov rsi, r13
    mov edx, DT_OUTLINE
    mov ecx, DT_TILE_H
    mov r8d, DT_TEXT
    call fb_fill_rect
    lea rdi, [r12 + DT_TILE_W - DT_OUTLINE]
    mov rsi, r13                    ; right
    mov edx, DT_OUTLINE
    mov ecx, DT_TILE_H
    mov r8d, DT_TEXT
    call fb_fill_rect
    add rsp, 8
    pop r13
    pop r12
    ret

align 8
dt_tiles:
    dt_tile dt_l_term, 8, 0, 0, 0x002e3440, '>'
    dt_tile dt_l_web, 7, cmd_browse, dt_empty, 0x005e81ac, 'W'
    dt_tile dt_l_glass, 5, cmd_glass, dt_empty, 0x00b48ead, 'G'
    dt_tile dt_l_edit, 6, cmd_edit, dt_edit_path, 0x00a3be8c, 'E'
    dt_tile dt_l_top, 7, cmd_top, dt_empty, 0x0088c0d0, 'M'
    dt_tile dt_l_snake, 5, cmd_run, dt_snake_path, 0x00ebcb8b, 'S'
    dt_tile dt_l_reboot, 6, cmd_reboot, 0, 0x00d08770, 'R'
    dt_tile dt_l_off, 9, cmd_shutdown, 0, 0x00bf616a, 'O'

dt_l_term        db "Terminal", 0
dt_l_web         db "Browser", 0
dt_l_glass       db "Glass", 0
dt_l_edit        db "Editor", 0
dt_l_top         db "Monitor", 0
dt_l_snake       db "Snake", 0
dt_l_reboot      db "Reboot", 0
dt_l_off         db "Shut down", 0
dt_msg_name      db "Vitre", 0
dt_msg_hint      db "click a tile or press 1 to 8; q goes back to the shell"
dt_msg_hint_len  equ $ - dt_msg_hint
                 db 0
dt_clock_layout  db "####-##-## ##:##", 0
dt_clock_len     equ $ - dt_clock_layout - 1
dt_edit_path     db "kernel/report.asm", 0
dt_snake_path    db "snake.asm", 0

section .bss
dt_empty      resb 1
dt_hover      resb 1                ; the outlined tile, DT_NONE for none
dt_clock_text resb 32
section .text
