; Browser: `browse [url]` takes the screen and shows the page laid out to
; its width, headings and links in their own colours, the title above and
; the address below. Keys: arrows or j and k scroll a line, space, PgDn
; and PgUp a screen, Home and End; a link's number then Enter follows it,
; g types an address, b goes back, q or Esc leave.

BR_URL_MAX   equ 256
BR_HISTORY   equ 16
BR_HINT_COLS equ 48

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
    xor eax, eax
    mov [rel br_depth], eax
    mov [rel br_pick], eax
    mov rsi, rdi
    cmp byte [rdi], 0
    jne .open
    mov [rel br_url], al
    lea rdi, [rel br_home]
    mov esi, br_home_len
    call br_layout
    jmp .frame
.open:
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
    cmp eax, 10
    je .follow
    cmp eax, 'g'
    je .go
    cmp eax, 'b'
    je .back
    cmp eax, 8
    je .back
    lea ecx, [rax - '0']
    cmp ecx, 9
    ja .key
    imul edx, [rel br_pick], 10
    add edx, ecx
    cmp edx, HTML_LINKS
    cmova edx, ecx                  ; too big: start again from this digit
    mov [rel br_pick], edx
    jmp .frame
.follow:
    mov eax, [rel br_pick]
    mov dword [rel br_pick], 0
    dec eax
    cmp eax, [rel html_link_count]
    jae .frame
    shl eax, 8                      ; HTML_HREF_MAX bytes a link
    lea rsi, [rel html_links]
    add rsi, rax
    call br_resolve
    jc .frame
    jmp .visit
.go:
    call br_prompt
    jc .frame
.visit:
    lea rsi, [rel br_next]
    call br_visit
    jmp .frame
.back:
    call br_back
    jmp .frame
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
    lea rdi, [rel br_url]
    call http_get
    jc .failed
    call http_body
    mov rdi, rax
    mov esi, ecx
    jmp br_layout
.failed:
    lea rdi, [rel br_msg_failed]
    mov esi, br_msg_failed_len

; name: br_layout
; in:   rdi = HTML, esi = length
; out:  the page laid out at the screen width, less the margins, shown
;       from the top
; clobbers: caller-saved
br_layout:
    mov dword [rel br_top], 0
    mov rdx, [rel kernel_console + CON_COLS]
    sub edx, 2                      ; the margins
    cmp edx, HTML_COLS
    jbe .width
    mov edx, HTML_COLS
.width:
    jmp html_layout

; name: br_visit
; in:   rsi = URL
; out:  the current page remembered for br_back unless BR_HISTORY are,
;       then the URL opened
; clobbers: caller-saved
br_visit:
    push rsi
    cmp byte [rel br_url], 0
    je .open
    mov eax, [rel br_depth]
    cmp eax, BR_HISTORY
    jae .open                       ; full: deeper pages are not remembered
    lea ecx, [rax + 1]
    mov [rel br_depth], ecx
    shl eax, 8                      ; BR_URL_MAX bytes a page
    lea rdi, [rel br_history]
    add rdi, rax
    lea rsi, [rel br_url]
    mov ecx, BR_URL_MAX
    rep movsb
.open:
    pop rsi
    jmp br_open

; name: br_back
; in:   none
; out:  the page before the current one opened, if there is one
; clobbers: caller-saved
br_back:
    mov eax, [rel br_depth]
    test eax, eax
    jz .done
    dec eax
    mov [rel br_depth], eax
    shl eax, 8
    lea rsi, [rel br_history]
    add rsi, rax
    jmp br_open
.done:
    ret

; name: br_resolve
; in:   rsi = a link's href
; out:  its full address in br_next, relative to br_url; CF=1 for a link
;       within the page
; clobbers: rax, rcx, rdx, rsi, rdi, r8, r9, r10
br_resolve:
    push rbx
    mov rbx, rsi
    lea rdi, [rel br_next]
    lea r8, [rdi + BR_URL_MAX - 2]  ; room for a '/' and the 0
    mov al, [rbx]
    test al, al
    jz .none
    cmp al, '#'
    je .none
    mov rdx, rbx                    ; the link's scheme, else the page's
    call br_after_scheme
    jc .scheme
    lea rdx, [rel br_url]
    call br_after_scheme
.scheme:
    lea rsi, [rel br_http]
    sub rax, rdx
    cmp eax, 8                      ; past "https://"
    jne .plain
    lea rsi, [rel br_https]
.plain:
    call br_append
    mov rdx, rbx
    call br_after_scheme
    mov rsi, rax
    jc .tail
    lea rsi, [rbx + 2]
    cmp word [rbx], '//'
    je .tail
    lea rdx, [rel br_url]
    call br_after_scheme
    mov rsi, rax
    xor r9d, r9d                    ; r9 = after the last '/' of the path
    xor r10d, r10d                  ; r10 = where the host ends
.base:
    mov al, [rsi]
    test al, al
    jz .based
    cmp rdi, r8
    jae .based
    cmp al, '/'
    jne .keep
    test r10, r10
    jnz .slash
    mov r10, rdi
.slash:
    lea r9, [rdi + 1]
.keep:
    stosb
    inc rsi
    jmp .base
.based:
    test r10, r10
    jnz .path
    mov r10, rdi                    ; no path: the root
    mov al, '/'
    stosb
    mov r9, rdi
.path:
    mov rdi, r9
    cmp byte [rbx], '/'
    jne .relative
    mov rdi, r10
.relative:
    mov rsi, rbx
.tail:
    call br_append
    mov byte [rdi], 0
    clc
    pop rbx
    ret
.none:
    stc
    pop rbx
    ret

; name: br_after_scheme
; in:   rdx = URL
; out:  rax = after its "http://" or "https://" and CF=1, or rax = rdx and
;       CF=0 if it has neither
; clobbers: rax
br_after_scheme:
    mov rax, rdx
    cmp dword [rax], 'http'
    jne .none
    add rax, 4
    cmp byte [rax], 's'
    jne .colon
    inc rax
.colon:
    cmp word [rax], ':/'
    jne .none
    cmp byte [rax + 2], '/'
    jne .none
    add rax, 3
    stc
    ret
.none:
    mov rax, rdx
    clc
    ret

; name: br_append
; in:   rsi = string, rdi = destination, r8 = where the destination ends
; out:  the string copied up to its 0 or r8; rdi after it, rsi after the
;       last byte read
; clobbers: rax, rsi, rdi
br_append:
    cmp rdi, r8
    jae .done
    lodsb
    test al, al
    jz .done
    stosb
    jmp br_append
.done:
    ret

; name: br_prompt
; in:   none
; out:  an address typed in the address bar, in br_next; CF=1 if Esc or
;       nothing was typed
; clobbers: caller-saved
br_prompt:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx                    ; ebx = length
    mov r12, [rel kernel_console + CON_ROWS]
    dec r12d                        ; r12 = the address bar's row
.draw:
    lea rax, [rel br_next]
    mov byte [rax + rbx], 0
    mov esi, r12d
    lea rdx, [rel br_msg_go]
    call gl_bar
    mov edi, 8                      ; after " go to:"
    mov esi, r12d
    lea rdx, [rel br_next]
    mov ecx, COLOR_FG
    mov r8d, GL_TITLE_BG
    call gl_text
    mov edi, eax
    mov esi, r12d
    lea rdx, [rel br_cursor]
    mov ecx, GL_ACCENT
    mov r8d, GL_TITLE_BG
    call gl_text
.key:
    call kbd_getc
    cmp eax, 10
    je .done
    cmp eax, KEY_ESC
    je .cancel
    cmp eax, 8
    je .erase
    cmp eax, ' '
    jbe .key
    cmp eax, 0x7f                   ; KEY_* codes are not text
    jae .key
    cmp ebx, BR_URL_MAX - 1
    jae .key
    lea rcx, [rel br_next]
    mov [rcx + rbx], al
    inc ebx
    jmp .draw
.erase:
    test ebx, ebx
    jz .key
    dec ebx
    jmp .draw
.done:
    test ebx, ebx
    jnz .out                        ; CF=0 from the test
.cancel:
    stc
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

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
    inc ebx                         ; ebx = the address bar's row
    mov esi, ebx
    lea rdx, [rel br_url]
    call gl_bar
    mov r12, [rel kernel_console + CON_COLS]
    sub r12d, BR_HINT_COLS          ; r12 = the hint's column
    mov eax, [rel br_pick]
    test eax, eax
    jnz .pick
    mov edi, r12d
    mov esi, ebx
    lea rdx, [rel br_msg_keys]
    mov ecx, GL_DIM
    mov r8d, GL_TITLE_BG
    call gl_text
    jmp .done
.pick:
    lea r13, [rel br_pick_text + 7] ; the number, written from the right
    mov byte [r13], 0
    mov ecx, 10
.digit:
    xor edx, edx
    div ecx
    add dl, '0'
    dec r13
    mov [r13], dl
    test eax, eax
    jnz .digit
    mov edi, r12d
    mov esi, ebx
    lea rdx, [rel br_msg_link]
    mov ecx, GL_ACCENT
    mov r8d, GL_TITLE_BG
    call gl_text
    mov edi, eax
    mov esi, ebx
    mov rdx, r13
    mov ecx, GL_ACCENT
    mov r8d, GL_TITLE_BG
    call gl_text
.done:
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
br_msg_keys       db "number+Enter link  g address  b back  q quit", 0
br_msg_link       db "Enter follows link ", 0
br_msg_go         db "go to:", 0
br_cursor         db "_", 0
br_http           db "http://", 0
br_https          db "https://", 0

br_home:
    db "<title>Vitre browser</title><h1>Vitre browser</h1>"
    db "<p>Press g, type an address such as example.com, then Enter.<p>Links show "
    db "a number after them: type it, then Enter, to follow the link. b goes back."
    db "<p>The arrows, j and k scroll a line; space, PgUp and PgDn a screen."
br_home_len equ $ - br_home

section .bss
br_top       resd 1
br_pick      resd 1
br_depth     resd 1
br_pick_text resb 8
br_url       resb BR_URL_MAX
br_next      resb BR_URL_MAX
br_history   resb BR_HISTORY * BR_URL_MAX
section .text
