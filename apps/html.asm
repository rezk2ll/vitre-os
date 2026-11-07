; HTML layout: turns a page into lines of cells, each with a style, for a
; given width. Words wrap at the width; tags are dropped.

HTML_COLS      equ 128              ; widest layout
HTML_LINES     equ 4096
HTML_WORD_MAX  equ HTML_COLS
HTML_VIEW_COLS equ 100

; cell styles
HTML_TEXT    equ 0

; name: html_layout
; in:   rdi = HTML, esi = length, edx = width in columns (at most HTML_COLS)
; out:  html_lines lines in html_text and html_style
; clobbers: caller-saved
html_layout:
    push rbx
    push r12
    push r13
    mov rbx, rdi                    ; rbx = position, r12 = end
    mov r12d, esi
    add r12, rdi
    mov r13d, edx                   ; r13 = width
    xor eax, eax
    mov [rel html_lines], eax
    mov [rel html_col], eax
    mov [rel html_word_len], eax
    mov byte [rel html_space], 0
    mov byte [rel html_style_now], HTML_TEXT
    lea rdi, [rel html_text]
    mov ecx, HTML_COLS
    mov al, ' '
    rep stosb
    lea rdi, [rel html_style]
    mov ecx, HTML_COLS
    xor eax, eax
    rep stosb
.next:
    cmp rbx, r12
    jae .end
    movzx eax, byte [rbx]
    inc rbx
    cmp al, '<'
    je .tag
    cmp al, ' '
    jbe .white
    mov edi, eax
    call html_char
    jmp .next
.white:
    call html_flush
    mov byte [rel html_space], 1
    jmp .next
.tag:
    call html_tag
    jmp .next
.end:
    call html_flush
    cmp dword [rel html_col], 0
    je .done
    inc dword [rel html_lines]
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: html_char
; in:   edi = character; the html_layout registers
; out:  added to the current word
; clobbers: rax, rcx, rdx, rsi, r8
html_char:
    mov eax, [rel html_word_len]
    cmp eax, r13d                   ; a word as wide as the line goes out now
    jb .add
    push rdi
    call html_flush
    pop rdi
    xor eax, eax
.add:
    lea rcx, [rel html_word]
    mov [rcx + rax], dil
    lea rcx, [rel html_word_style]
    mov dl, [rel html_style_now]
    mov [rcx + rax], dl
    inc eax
    mov [rel html_word_len], eax
    ret

; name: html_flush
; in:   the html_layout registers
; out:  the current word placed on the current line, after a space if one
;       was seen, on a new line if it does not fit
; clobbers: rax, rcx, rdx, rsi, rdi, r8
html_flush:
    mov ecx, [rel html_word_len]
    test ecx, ecx
    jz .done
    mov eax, [rel html_col]
    test eax, eax
    jz .place
    cmp byte [rel html_space], 0
    je .fits
    inc eax                         ; the space before it
.fits:
    add eax, ecx
    cmp eax, r13d
    jbe .spaced
    call html_newline
    jmp .place
.spaced:
    cmp byte [rel html_space], 0
    je .place
    inc dword [rel html_col]
.place:
    call html_cell_at               ; rdi = text cell, rsi = style cell
    mov ecx, [rel html_word_len]
    add [rel html_col], ecx
    lea r8, [rel html_word]
    lea rdx, [rel html_word_style]
.copy:
    mov al, [r8]
    mov [rdi], al
    mov al, [rdx]
    mov [rsi], al
    inc r8
    inc rdx
    inc rdi
    inc rsi
    dec ecx
    jnz .copy
    mov dword [rel html_word_len], 0
.done:
    mov byte [rel html_space], 0
    ret

; name: html_cell_at
; in:   none
; out:  rdi = text cell at the current line and column, rsi = its style
; clobbers: rax, rdi, rsi
html_cell_at:
    mov eax, [rel html_lines]
    shl eax, 7                      ; HTML_COLS cells a line
    add eax, [rel html_col]
    lea rdi, [rel html_text]
    add rdi, rax
    lea rsi, [rel html_style]
    add rsi, rax
    ret

; name: html_newline
; in:   none
; out:  a new, blank line started, unless the document is full
; clobbers: rax, rcx, rdi
html_newline:
    mov dword [rel html_col], 0
    mov eax, [rel html_lines]
    cmp eax, HTML_LINES - 1
    jae .full
    inc eax
    mov [rel html_lines], eax
.full:
    shl eax, 7
    lea rdi, [rel html_text]
    add rdi, rax
    mov ecx, HTML_COLS
    mov al, ' '
    rep stosb
    mov eax, [rel html_lines]
    shl eax, 7
    lea rdi, [rel html_style]
    add rdi, rax
    mov ecx, HTML_COLS
    xor eax, eax
    rep stosb
    ret

; name: html_tag
; in:   rbx = after "<", r12 = end
; out:  rbx past its ">"
; clobbers: none
html_tag:
    cmp rbx, r12
    jae .done
    inc rbx
    cmp byte [rbx - 1], '>'
    jne html_tag
.done:
    ret

; name: cmd_view
; in:   rdi = URL
; out:  the page fetched, laid out HTML_VIEW_COLS wide and printed
; clobbers: caller-saved
cmd_view:
    push rbx
    push r12
    push r13
    cmp byte [rel net_ready], 0
    je .no_net
    call http_get
    jc .failed
    call http_body
    mov rdi, rax
    mov esi, ecx
    mov edx, HTML_VIEW_COLS
    call html_layout
    xor ebx, ebx
.line:
    cmp ebx, [rel html_lines]
    jae .done
    mov r12d, ebx
    shl r12d, 7
    lea rax, [rel html_text]
    add r12, rax
    mov r13d, HTML_VIEW_COLS        ; trailing spaces are not printed
.trim:
    test r13d, r13d
    jz .print_line
    cmp byte [r12 + r13 - 1], ' '
    jne .print_line
    dec r13d
    jmp .trim
.print_line:
    test r13d, r13d
    jz .eol
    movzx edi, byte [r12]
    inc r12
    dec r13d
    call kputc
    jmp .print_line
.eol:
    mov edi, 10
    call kputc
    inc ebx
    jmp .line
.failed:
    lea rdi, [rel http_msg_failed]
    call kputs
    jmp .done
.no_net:
    lea rdi, [rel net_msg_none]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

section .bss
alignb 8
html_lines      resd 1
html_col        resd 1
html_word_len   resd 1
html_space      resb 1
html_style_now  resb 1
html_word       resb HTML_WORD_MAX
html_word_style resb HTML_WORD_MAX
alignb 4096
html_text       resb HTML_LINES * HTML_COLS
html_style      resb HTML_LINES * HTML_COLS
section .text
