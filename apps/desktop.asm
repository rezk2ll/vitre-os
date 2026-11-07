; Desktop: `desktop` takes the screen and shows a bar with the clock and an
; icon per app and per user file, in columns from the top left. The icon
; under the pointer is outlined. A click opens it: an app starts, a program
; runs, any other file opens in the editor, and the desktop comes back when
; it ends. A right click opens a menu: Open, Edit and Delete on a file, New
; file on the desktop. q or Esc return to the shell.

DT_BAR_H    equ 24
DT_MARGIN   equ 16
DT_CELL_W   equ 112
DT_CELL_H   equ 104
DT_ICON     equ 64                  ; the icon square, at the top of its cell
DT_ICON_X   equ (DT_CELL_W - DT_ICON) / 2
DT_LABEL    equ 13                  ; label characters shown under an icon
DT_ENTRY    equ 32                  ; label, action, argument, colour, letter
DT_APPS     equ 9
DT_MAX      equ 64
DT_SCALE    equ 4                   ; icon letters are the font at 4x
DT_OUTLINE  equ 3                   ; the hovered icon's border, in pixels
DT_NONE     equ 0xff
DT_BAR_BG   equ 0x000f141e
DT_TEXT     equ 0x00eceff4
DT_DIM      equ 0x009aa5b8
DT_PROGRAM  equ 0x00ebcb8b
DT_DOC      equ 0x0081a1c1
DT_MENU_W   equ 136
DT_ROW      equ 24                  ; a menu entry's height
DT_MENU_BG  equ 0x003b4252

%macro dt_app 5                     ; label, action, argument, colour, letter
    dq %1, %2, %3
    dd %4
    db %5, 0, 0, 0
%endmacro

; name: cmd_desktop
; in:   rdi = arguments (ignored)
; out:  the desktop ran until q, Esc or the Terminal icon; screen cleared
; clobbers: caller-saved
cmd_desktop:
    push rbx
    push r12
    cmp byte [rel console_ready], 0
    je .no_screen
.redraw:
    call dt_build
    call dt_draw
    call mouse_click                ; forget clicks made in the app
    call mouse_rclick
    mov byte [rel dt_hover], DT_NONE
    mov r12, [rel timer_ticks]
.loop:
    call kbd_poll
    jnz .key
    call mouse_click
    jc .right
    call dt_hit
    jc .right
    mov edi, eax
    call dt_launch
    jc .quit
    jmp .redraw
.right:
    call mouse_rclick
    jc .hover
    call dt_menu
    jc .quit
    jmp .redraw
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
    jne .loop
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

; name: dt_build
; in:   none
; out:  dt_items holds the apps, then an icon per user file; dt_count set
; clobbers: rax, rcx, rdx, rdi, rsi
dt_build:
    lea rsi, [rel dt_apps]
    lea rdi, [rel dt_items]
    mov ecx, DT_APPS * DT_ENTRY
    rep movsb
    mov dword [rel dt_count], DT_APPS
    mov rsi, [rel src_area]
    test rsi, rsi
    jz .ret
    mov ecx, [rsi + SRC_HDR_COUNT]
    add rsi, SRC_DIR
.file:
    test ecx, ecx
    jz .ret
    cmp dword [rel dt_count], DT_MAX
    jae .ret
    test dword [rsi + SRC_DIR_FLAGS], SRC_FILE
    jz .next
    mov eax, [rel dt_count]
    imul eax, eax, DT_ENTRY
    lea rdi, [rel dt_items]
    add rdi, rax
    mov [rdi], rsi                  ; an entry starts with its name
    lea rax, [rel dt_open]
    mov [rdi + 8], rax
    mov [rdi + 16], rsi
    mov dword [rdi + 24], DT_DOC
    push rdi
    mov rdi, rsi
    call str_skip
    pop rdi
    cmp dword [rax - 5], ".asm"
    jne .letter
    mov dword [rdi + 24], DT_PROGRAM
.letter:
    movzx eax, byte [rsi]           ; the name's first letter, upper case
    lea edx, [rax - 'a']
    cmp edx, 'z' - 'a'
    ja .upper
    sub eax, 'a' - 'A'
.upper:
    mov [rdi + 28], al
    inc dword [rel dt_count]
.next:
    add rsi, SRC_DIR_ENTRY
    dec ecx
    jmp .file
.ret:
    ret

; name: dt_open
; in:   rdi = file name
; out:  a .asm file run, then dt_await; any other file edited
; clobbers: caller-saved
dt_open:
    push rbx
    call dt_keep
    mov rbx, rdi
    call str_skip
    cmp dword [rax - 5], ".asm"
    jne .edit
    mov rdi, rbx
    call cmd_run
    call dt_await
    jmp .done
.edit:
    mov rdi, rbx
    call cmd_edit
.done:
    pop rbx
    ret

; name: dt_keep
; in:   rdi = file name
; out:  rdi = dt_name holding a copy, safe when the source area moves
; clobbers: rcx, rsi, rdi
dt_keep:
    mov rsi, rdi
    lea rdi, [rel dt_name]
    mov ecx, SRC_NAME_MAX + 1
    rep movsb
    lea rdi, [rel dt_name]
    ret

; name: dt_launch
; in:   edi = icon index
; out:  its app or file opened and ended; CF=1 for Terminal, back to the shell
; clobbers: caller-saved
dt_launch:
    push rbx
    imul eax, edi, DT_ENTRY
    lea rbx, [rel dt_items]
    add rbx, rax
    cmp qword [rbx + 8], 0
    stc
    je .ret
    call shell_clear_screen
    mov rdi, [rbx + 16]
    call [rbx + 8]
    clc
.ret:
    pop rbx
    ret

; name: dt_edit
; in:   edi = icon index of a file
; out:  the file edited
; clobbers: caller-saved
dt_edit:
    sub rsp, 8
    imul eax, edi, DT_ENTRY
    lea rdi, [rel dt_items]
    mov rdi, [rdi + rax + 16]
    call dt_keep
    push rdi
    call shell_clear_screen
    pop rdi
    call cmd_edit
    add rsp, 8
    clc
    ret

; name: dt_delete
; in:   edi = icon index of a file
; out:  the file removed once y confirms it in the bar
; clobbers: caller-saved
dt_delete:
    push rbx
    imul eax, edi, DT_ENTRY
    lea rdi, [rel dt_items]
    mov rdi, [rdi + rax + 16]
    call dt_keep
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov ecx, DT_BAR_H
    mov r8d, DT_BAR_BG
    call fb_fill_rect
    mov edi, 12
    mov esi, 4
    lea rdx, [rel dt_msg_delete]
    mov ecx, DT_TEXT
    mov r8d, DT_BAR_BG
    call dt_text
    lea rdi, [rel dt_name]
    call str_skip
    lea rbx, [rel dt_name + 1]
    sub rax, rbx                    ; the name's length
    lea rbx, [rax * 8 + 12 + dt_msg_delete_len * 8]
    mov edi, 12 + dt_msg_delete_len * 8
    mov esi, 4
    lea rdx, [rel dt_name]
    mov ecx, DT_TEXT
    mov r8d, DT_BAR_BG
    call dt_text
    mov rdi, rbx
    mov esi, 4
    lea rdx, [rel dt_msg_sure]
    mov ecx, DT_DIM
    mov r8d, DT_BAR_BG
    call dt_text
.wait:
    call task_yield
    call kbd_poll
    jz .wait
    cmp eax, 'y'
    jne .ret
    lea rdi, [rel dt_name]
    call src_remove
.ret:
    clc
    pop rbx
    ret

; name: dt_new
; in:   none
; out:  a name asked for on the console, then that file opened in the editor
; clobbers: caller-saved
dt_new:
    sub rsp, 8
    call shell_clear_screen
    lea rdi, [rel dt_msg_new]
    call kputs
    lea rdi, [rel dt_line]
    call shell_readline
    test rax, rax
    jz .ret
    lea rdi, [rel dt_line]
    call cmd_edit
.ret:
    add rsp, 8
    clc
    ret

; name: dt_video
; in:   none
; out:  a URL asked for on the console and played, then a key or click
;       awaited
; clobbers: caller-saved
dt_video:
    sub rsp, 8
    lea rdi, [rel dt_msg_video]
    call kputs
    lea rdi, [rel dt_line]
    call shell_readline
    test rax, rax
    jz .ret
    lea rdi, [rel dt_line]
    call cmd_play
    call dt_await
.ret:
    add rsp, 8
    ret

; name: dt_await
; in:   none
; out:  a key pressed or a click made after a hint saying so
; clobbers: caller-saved
dt_await:
    sub rsp, 8
    lea rdi, [rel dt_msg_back]
    call kputs
    call mouse_click
.wait:
    call kbd_poll
    jnz .ret
    call mouse_click
    jnc .ret
    call task_yield
    jmp .wait
.ret:
    add rsp, 8
    ret

; name: dt_menu
; in:   mouse_x, mouse_y
; out:  a menu at the pointer for the icon under it, or for the desktop; the
;       entry clicked done. CF=1 if it was Open on Terminal
; clobbers: caller-saved
dt_menu:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r15, [rel dt_menu_desk]
    call dt_hit
    mov r14d, eax                   ; the icon the entries act on
    jc .place
    lea r15, [rel dt_menu_file]
    cmp eax, DT_APPS
    jae .place
    lea r15, [rel dt_menu_app]
.place:
    xor ebx, ebx                    ; entries
.count:
    cmp qword [r15 + rbx * 8], 0
    je .counted
    add ebx, 2
    jmp .count
.counted:
    shr ebx, 1
    mov r12d, [rel mouse_x]         ; kept on the screen
    mov rax, [rel fb_width]
    sub rax, DT_MENU_W
    cmp r12, rax
    cmova r12, rax
    mov r13d, [rel mouse_y]
    imul ecx, ebx, DT_ROW
    mov rax, [rel fb_height]
    sub rax, rcx
    cmp r13, rax
    cmova r13, rax
    mov rdi, r12
    mov rsi, r13
    mov edx, DT_MENU_W
    mov r8d, DT_MENU_BG
    call fb_fill_rect
    xor ecx, ecx
.entry:
    cmp ecx, ebx
    jae .wait
    push rcx
    push rcx
    lea rdi, [r12 + 12]
    imul esi, ecx, DT_ROW
    lea rsi, [r13 + rsi + (DT_ROW - 16) / 2]
    shl ecx, 4
    mov rdx, [r15 + rcx]
    mov ecx, DT_TEXT
    mov r8d, DT_MENU_BG
    call dt_text
    pop rcx
    pop rcx
    inc ecx
    jmp .entry
.wait:
    call task_yield
    call kbd_poll
    jnz .cancel
    call mouse_rclick
    jnc .cancel
    call mouse_click
    jc .wait
    mov eax, [rel mouse_x]
    sub rax, r12
    cmp rax, DT_MENU_W
    jae .cancel
    mov eax, [rel mouse_y]
    sub rax, r13
    xor edx, edx
    mov ecx, DT_ROW
    div rcx
    cmp eax, ebx
    jae .cancel
    shl eax, 4
    mov edi, r14d
    call [r15 + rax + 8]
    jmp .ret
.cancel:
    clc
.ret:
    pop r15
    pop r14
    pop r13
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
    mov edi, ebx
    call dt_shade
    mov r8d, eax
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
.icon:
    cmp ebx, [rel dt_count]
    jae .hint
    mov edi, ebx
    call dt_icon_draw
    mov edi, ebx
    call dt_label_draw
    inc ebx
    jmp .icon
.hint:
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

; name: dt_shade
; in:   edi = screen row
; out:  eax = the background colour of that row
; clobbers: rax, rcx, rdx
dt_shade:
    mov eax, edi
    imul eax, eax, 0x30
    xor edx, edx
    div qword [rel fb_height]
    lea ecx, [rax + 0x18]
    shl ecx, 8
    mov eax, edi
    imul eax, eax, 0x40
    xor edx, edx
    div qword [rel fb_height]
    lea ecx, [rcx + rax + 0x24]
    shl ecx, 8
    mov eax, edi
    imul eax, eax, 0x60
    xor edx, edx
    div qword [rel fb_height]
    lea eax, [rcx + rax + 0x3c]
    ret

; name: dt_origin
; in:   edi = icon index
; out:  rax = its cell's left edge, rdx = its cell's top edge
; clobbers: rax, rcx, rdx
dt_origin:
    mov rax, [rel fb_height]        ; icons fill a column, then the next
    sub rax, DT_BAR_H + DT_MARGIN
    xor edx, edx
    mov ecx, DT_CELL_H
    div rcx
    mov ecx, eax                    ; rows in a column
    mov eax, edi
    xor edx, edx
    div ecx                         ; eax = column, edx = row
    imul eax, eax, DT_CELL_W
    add eax, DT_MARGIN
    imul edx, edx, DT_CELL_H
    add edx, DT_BAR_H + DT_MARGIN
    ret

; name: dt_icon_draw
; in:   edi = icon index
; out:  the icon square drawn in its colour, its letter large
; clobbers: caller-saved
dt_icon_draw:
    push rbx
    push r12
    push r13
    imul eax, edi, DT_ENTRY
    lea rbx, [rel dt_items]
    add rbx, rax
    call dt_origin
    lea r12, [rax + DT_ICON_X]
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    mov edx, DT_ICON
    mov ecx, DT_ICON
    mov r8d, [rbx + 24]
    call fb_fill_rect
    lea rdi, [r12 + (DT_ICON - 8 * DT_SCALE) / 2]
    mov rsi, r13
    movzx edx, byte [rbx + 28]
    mov ecx, DT_TEXT
    call dt_big
    pop r13
    pop r12
    pop rbx
    ret

; name: dt_label_draw
; in:   edi = icon index
; out:  its label drawn under the icon, centred, cut to DT_LABEL characters
; clobbers: caller-saved
dt_label_draw:
    push rbx
    push r12
    push r13
    push r14
    push r15
    imul eax, edi, DT_ENTRY
    lea rbx, [rel dt_items]
    mov rbx, [rbx + rax]
    call dt_origin
    mov r12, rax
    lea r13, [rdx + DT_ICON + 8]
    xor r14d, r14d                  ; characters shown
.length:
    cmp r14d, DT_LABEL
    jae .measured
    cmp byte [rbx + r14], 0
    je .measured
    inc r14d
    jmp .length
.measured:
    lea eax, [r14 * 4]              ; centre: half of 8 pixels a character
    lea r12, [r12 + DT_CELL_W / 2]
    sub r12, rax
    mov edi, r13d
    add edi, 8
    call dt_shade
    mov r15d, eax
.char:
    test r14d, r14d
    jz .done
    mov rdi, r12
    mov rsi, r13
    movzx edx, byte [rbx]
    mov ecx, DT_TEXT
    mov r8d, r15d
    call fb_draw_glyph
    add r12, 8
    inc rbx
    dec r14d
    jmp .char
.done:
    pop r15
    pop r14
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
; out:  eax = the icon whose cell is under the pointer; CF=1 if none
; clobbers: rax, rcx, rdx, rdi
dt_hit:
    xor edi, edi
.icon:
    cmp edi, [rel dt_count]
    jae .none
    call dt_origin
    mov ecx, [rel mouse_x]
    sub rcx, rax
    cmp rcx, DT_CELL_W              ; unsigned: left of it wraps around
    jae .next
    mov ecx, [rel mouse_y]
    sub rcx, rdx
    cmp rcx, DT_CELL_H
    jae .next
    mov eax, edi
    clc
    ret
.next:
    inc edi
    jmp .icon
.none:
    stc
    ret

; name: dt_hover_update
; in:   none
; out:  the icon under the pointer outlined, the one before drawn plain
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
    call dt_icon_draw
.outline:
    cmp ebx, DT_NONE
    je .ret
    mov edi, ebx
    call dt_outline
.ret:
    pop rbx
    ret

; name: dt_outline
; in:   edi = icon index
; out:  a light border drawn just inside the icon square
; clobbers: caller-saved
dt_outline:
    push r12
    push r13
    sub rsp, 8
    call dt_origin
    lea r12, [rax + DT_ICON_X]
    mov r13, rdx
    mov rdi, r12                    ; top
    mov rsi, r13
    mov edx, DT_ICON
    mov ecx, DT_OUTLINE
    mov r8d, DT_TEXT
    call fb_fill_rect
    mov rdi, r12                    ; bottom
    lea rsi, [r13 + DT_ICON - DT_OUTLINE]
    mov edx, DT_ICON
    mov ecx, DT_OUTLINE
    mov r8d, DT_TEXT
    call fb_fill_rect
    mov rdi, r12                    ; left
    mov rsi, r13
    mov edx, DT_OUTLINE
    mov ecx, DT_ICON
    mov r8d, DT_TEXT
    call fb_fill_rect
    lea rdi, [r12 + DT_ICON - DT_OUTLINE]
    mov rsi, r13                    ; right
    mov edx, DT_OUTLINE
    mov ecx, DT_ICON
    mov r8d, DT_TEXT
    call fb_fill_rect
    add rsp, 8
    pop r13
    pop r12
    ret

align 8
dt_apps:
    dt_app dt_l_term, 0, 0, 0x002e3440, '>'
    dt_app dt_l_web, cmd_browse, dt_empty, 0x005e81ac, 'W'
    dt_app dt_l_video, dt_video, 0, 0x00d8a0c0, 'V'
    dt_app dt_l_paint, cmd_paint, dt_empty, 0x00ebcb8b, 'P'
    dt_app dt_l_glass, cmd_glass, dt_empty, 0x00b48ead, 'G'
    dt_app dt_l_files, cmd_files, dt_empty, 0x00a3be8c, 'F'
    dt_app dt_l_top, cmd_top, dt_empty, 0x0088c0d0, 'M'
    dt_app dt_l_reboot, cmd_reboot, 0, 0x00d08770, 'R'
    dt_app dt_l_off, cmd_shutdown, 0, 0x00bf616a, 'O'

dt_menu_app      dq dt_m_open, dt_launch, 0
dt_menu_file     dq dt_m_open, dt_launch, dt_m_edit, dt_edit, dt_m_delete, dt_delete, 0
dt_menu_desk     dq dt_m_new, dt_new, 0

dt_m_open        db "Open", 0
dt_m_edit        db "Edit", 0
dt_m_delete      db "Delete", 0
dt_m_new         db "New file", 0
dt_msg_new       db "new file name, empty cancels: ", 0
dt_msg_delete    db "delete "
dt_msg_delete_len equ $ - dt_msg_delete
                 db 0
dt_msg_sure      db "? y deletes it, any other key keeps it", 0
dt_l_term        db "Terminal", 0
dt_l_web         db "Browser", 0
dt_l_video       db "Video", 0
dt_msg_video     db "video URL, empty cancels: ", 0
dt_l_paint       db "Paint", 0
dt_l_glass       db "Glass", 0
dt_l_files       db "Files", 0
dt_l_top         db "Monitor", 0
dt_l_reboot      db "Reboot", 0
dt_l_off         db "Shut down", 0
dt_msg_name      db "Vitre", 0
dt_msg_hint      db "click an icon to open it; q goes back to the shell"
dt_msg_hint_len  equ $ - dt_msg_hint
                 db 0
dt_msg_back      db 10, "[desktop] press a key or click to go back", 10, 0
dt_clock_layout  db "####-##-## ##:##", 0
dt_clock_len     equ $ - dt_clock_layout - 1

section .bss
dt_empty      resb 1
dt_hover      resb 1                ; the outlined icon, DT_NONE for none
dt_clock_text resb 32
dt_name       resb SRC_NAME_MAX + 1
dt_line       resb SHELL_LINE_MAX
alignb 8
dt_count      resd 1
alignb 8
dt_items      resb DT_MAX * DT_ENTRY
section .text
