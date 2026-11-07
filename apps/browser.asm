; Browser: `browse <url>` takes the screen and shows the page laid out to
; its width, headings and links in their own colours, the title above and
; the address below. Keys: arrows or j and k scroll a line, space, PgDn
; and PgUp a screen, Home and End, q or Esc leave.

BR_URL_MAX equ 256

; name: cmd_browse
; in:   rdi = URL
; out:  the browser ran until q or Esc; the screen is cleared
; clobbers: caller-saved
cmd_browse:
    push rbx
    cmp byte [rel console_ready], 0
    je .no_screen
    cmp byte [rel net_ready], 0
    je .no_net
    mov rsi, rdi
    call br_open
.frame:
    call br_render
.key:
    call kbd_getc
    mov rbx, [rel kernel_console + CON_ROWS]
    sub ebx, 2                      ; a screen of lines
    cmp eax, ' '
    je .down
    cmp eax, KEY_PGDN
    je .down
    cmp eax, KEY_PGUP
    je .up
    cmp eax, KEY_HOME
    je .home
    cmp eax, KEY_END
    je .end
    mov ebx, 1
    cmp eax, KEY_DOWN
    je .down
    cmp eax, 'j'
    je .down
    cmp eax, KEY_UP
    je .up
    cmp eax, 'k'
    je .up
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    jmp .key
.down:
    add [rel br_top], ebx
    jmp .clamp
.up:
    sub [rel br_top], ebx
    jmp .clamp
.home:
    mov dword [rel br_top], 0
    jmp .frame
.end:
    mov dword [rel br_top], 0x7fffffff
.clamp:
    call br_clamp
    jmp .frame
.quit:
    call shell_clear_screen
    jmp .done
.no_screen:
    lea rdi, [rel br_msg_no_screen]
    call kputs
    jmp .done
.no_net:
    lea rdi, [rel net_msg_none]
    call kputs
.done:
    pop rbx
    ret

; name: br_open
; in:   rsi = URL
; out:  the URL in br_url, the page fetched and laid out at the screen
;       width, br_top 0; a page that does not load is a one-line message
; clobbers: caller-saved
br_open:
    lea rdi, [rel br_url]
    mov ecx, BR_URL_MAX - 1
.copy:
    lodsb
    test al, al
    jz .copied
    stosb
    loop .copy
.copied:
    mov byte [rdi], 0
    mov dword [rel br_top], 0
    lea rdi, [rel br_url]
    call http_get
    jc .failed
    call http_body
    mov rdi, rax
    mov esi, ecx
    jmp .layout
.failed:
    lea rdi, [rel br_msg_failed]
    mov esi, br_msg_failed_len
.layout:
    mov rdx, [rel kernel_console + CON_COLS]
    sub edx, 2                      ; the margins
    cmp edx, HTML_COLS
    jbe .width
    mov edx, HTML_COLS
.width:
    jmp html_layout

; name: br_clamp
; in:   br_top, possibly past either end
; out:  br_top within the page, so the last screen is full when it can be
; clobbers: rax, rcx, rdx
br_clamp:
    mov eax, [rel html_lines]
    mov rcx, [rel kernel_console + CON_ROWS]
    sub eax, ecx
    add eax, 2                      ; eax = the last top line
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    mov edx, [rel br_top]
    cmp edx, eax
    cmovg edx, eax
    test edx, edx
    cmovs edx, ecx
    mov [rel br_top], edx
    ret

; name: br_render
; in:   a page laid out, br_top
; out:  the title bar, the page from line br_top and the address bar drawn
; clobbers: caller-saved
br_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor esi, esi
    lea rdx, [rel html_title]
    cmp byte [rdx], 0
    jne .title
    lea rdx, [rel br_url]
.title:
    call gl_bar
    mov rbx, [rel kernel_console + CON_ROWS]
    sub ebx, 2                      ; ebx = page rows
    xor r12d, r12d                  ; r12 = page row
.row:
    cmp r12d, ebx
    jae .address
    mov r13d, [rel br_top]
    add r13d, r12d                  ; r13 = line
    xor r14d, r14d                  ; r14 = column
.cell:
    cmp r14, [rel kernel_console + CON_COLS]
    jae .next_row
    mov edx, ' '
    mov ecx, COLOR_FG
    cmp r13d, [rel html_lines]
    jae .draw
    lea eax, [r14 - 1]              ; one column of margin
    cmp eax, HTML_COLS
    jae .draw
    mov r15d, r13d
    shl r15d, 7
    add eax, r15d
    lea r15, [rel html_text]
    movzx edx, byte [r15 + rax]
    lea r15, [rel html_style]
    movzx eax, byte [r15 + rax]
    lea r15, [rel br_colours]
    mov ecx, [r15 + rax * 4]
.draw:
    lea edi, [r14 * 8]
    lea esi, [r12 + 1]
    shl esi, 4
    mov r8d, COLOR_BG
    call fb_draw_glyph
    inc r14d
    jmp .cell
.next_row:
    inc r12d
    jmp .row
.address:
    lea esi, [rbx + 1]
    lea rdx, [rel br_url]
    call gl_bar
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; by html cell style
br_colours dd COLOR_FG, GL_CHANGED, GL_ACCENT, GL_DIM

br_msg_failed     db "<p>This page did not load."
br_msg_failed_len equ $ - br_msg_failed
br_msg_no_screen  db "[browse] needs the screen", 10, 0

section .bss
br_top resd 1
br_url resb BR_URL_MAX
section .text
