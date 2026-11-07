; HTML layout: turns a page into lines of cells, each with a style, for a
; given width. Blocks break lines, words wrap, links get a number shown
; after them as "[n]". Scripts, styles and comments are skipped.

HTML_COLS      equ 128              ; widest layout
HTML_LINES     equ 4096
HTML_LINKS     equ 128
HTML_HREF_MAX  equ 256
HTML_TITLE_MAX equ 128
HTML_WORD_MAX  equ HTML_COLS
HTML_TAG_MAX   equ 16
HTML_VIEW_COLS equ 100

; cell styles
HTML_TEXT    equ 0
HTML_HEADING equ 1
HTML_LINK    equ 2
HTML_MARK    equ 3                  ; a link number

; tag kinds
HTML_K_BLOCK equ 1                  ; breaks the line
HTML_K_PARA  equ 2                  ; breaks the line and leaves a blank one
HTML_K_HEAD  equ 3                  ; a heading: a paragraph in its own style
HTML_K_TITLE equ 4
HTML_K_SKIP  equ 5                  ; its content is not shown
HTML_K_LINK  equ 6
HTML_K_ITEM  equ 7                  ; a list item
HTML_K_RULE  equ 8

; name: html_layout
; in:   rdi = HTML, esi = length, edx = width in columns (at most HTML_COLS)
; out:  html_lines lines in html_text and html_style, html_title, and
;       html_link_count links in html_links
; clobbers: caller-saved
html_layout:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi                    ; rbx = position, r12 = end
    mov r12d, esi
    add r12, rdi
    mov r13d, edx                   ; r13 = width
    xor eax, eax
    mov [rel html_lines], eax
    mov [rel html_col], eax
    mov [rel html_word_len], eax
    mov [rel html_title_len], eax
    mov [rel html_link_count], eax
    mov byte [rel html_space], 0
    mov byte [rel html_style_now], HTML_TEXT
    mov byte [rel html_in_title], 0
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
    cmp al, '&'
    je .entity
    cmp al, ' '
    jbe .white
.char:
    mov edi, eax
    call html_char
    jmp .next
.white:
    call html_flush
    mov byte [rel html_space], 1
    jmp .next
.entity:
    call html_entity
    jmp .char
.tag:
    call html_tag
    jmp .next
.end:
    call html_flush
    cmp dword [rel html_col], 0
    je .done
    inc dword [rel html_lines]
.done:
    mov eax, [rel html_title_len]
    lea rcx, [rel html_title]
    mov byte [rcx + rax], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: html_char
; in:   edi = character; the html_layout registers
; out:  added to the title or to the current word
; clobbers: rax, rcx, rdx, rsi, r8
html_char:
    cmp byte [rel html_in_title], 0
    je .word
    mov eax, [rel html_title_len]
    cmp eax, HTML_TITLE_MAX - 1
    jae .done
    cmp byte [rel html_space], 0    ; one space between title words
    je .title_char
    test eax, eax
    jz .title_char
    lea rcx, [rel html_title]
    mov byte [rcx + rax], ' '
    inc eax
    cmp eax, HTML_TITLE_MAX - 1
    jae .title_end
.title_char:
    lea rcx, [rel html_title]
    mov [rcx + rax], dil
    inc eax
.title_end:
    mov [rel html_title_len], eax
    mov byte [rel html_space], 0
.done:
    ret
.word:
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

; name: html_break
; in:   esi = 1 to leave a blank line as well
; out:  the current line ended if it has text; with esi = 1, a blank line
;       follows unless the one before is already blank
; clobbers: rax, rcx, rdx, rsi, rdi, r8
html_break:
    push rsi
    call html_flush
    pop rsi
    cmp dword [rel html_col], 0
    je .ended
    call html_newline
.ended:
    test esi, esi
    jz .done
    mov eax, [rel html_lines]
    test eax, eax
    jz .done                        ; nothing above to separate from
    dec eax
    shl eax, 7
    lea rdi, [rel html_text]
    add rdi, rax
    mov ecx, HTML_COLS
    mov al, ' '
    repe scasb
    je .done                        ; the line above is blank already
    call html_newline
.done:
    mov byte [rel html_space], 0
    ret

; name: html_entity
; in:   rbx = after "&", r12 = end
; out:  eax = the character; rbx past the entity, or unmoved with eax = '&'
;       if it is not one
; clobbers: rax, rcx, rdx, rsi, rdi
html_entity:
    lea rsi, [rel html_entities]
.try:
    movzx eax, byte [rsi]           ; the character, then the name and ';'
    test eax, eax
    jz .number
    lea rdi, [rsi + 1]
    mov rdx, rbx
.match:
    mov cl, [rdi]
    cmp rdx, r12
    jae .skip
    cmp cl, [rdx]
    jne .skip
    inc rdi
    inc rdx
    cmp cl, ';'
    jne .match
    mov rbx, rdx
    ret
.skip:
    inc rdi
    cmp byte [rdi - 1], ';'
    jne .skip
    mov rsi, rdi
    jmp .try
.number:
    mov rdx, rbx                    ; "#NNN;"
    cmp rdx, r12
    jae .not
    cmp byte [rdx], '#'
    jne .not
    inc rdx
    xor eax, eax
.digit:
    cmp rdx, r12
    jae .not
    movzx ecx, byte [rdx]
    inc rdx
    cmp ecx, ';'
    je .number_end
    sub ecx, '0'
    cmp ecx, 9
    ja .not
    imul eax, eax, 10
    add eax, ecx
    jmp .digit
.number_end:
    mov rbx, rdx
    cmp eax, 255
    jbe .done
    mov eax, '?'                    ; outside the font
.done:
    ret
.not:
    mov eax, '&'
    ret

; name: html_tag
; in:   rbx = after "<", r12 = end; the html_layout registers
; out:  the tag applied, rbx past its ">"
; clobbers: caller-saved except the html_layout registers
html_tag:
    lea rax, [rbx + 3]              ; a comment runs to "-->"
    cmp rax, r12
    ja .name
    cmp word [rbx], '!-'
    jne .name
    cmp byte [rbx + 2], '-'
    jne .name
    add rbx, 3
.comment:
    lea rax, [rbx + 3]
    cmp rax, r12
    ja .to_end
    cmp word [rbx], '--'
    jne .comment_next
    cmp byte [rbx + 2], '>'
    je .comment_end
.comment_next:
    inc rbx
    jmp .comment
.comment_end:
    add rbx, 3
    ret
.to_end:
    mov rbx, r12
    ret
.name:
    xor r14d, r14d                  ; r14 = 1 for a closing tag
    cmp rbx, r12
    jae .to_end
    cmp byte [rbx], '/'
    jne .read
    inc rbx
    inc r14d
.read:
    lea rdi, [rel html_tag_name]
    xor ecx, ecx
.name_char:
    cmp rbx, r12
    jae .named
    movzx eax, byte [rbx]
    cmp al, '>'
    je .named
    cmp al, ' '
    jbe .named
    cmp al, '/'
    je .named
    inc rbx
    cmp ecx, HTML_TAG_MAX - 1
    jae .name_char
    lea edx, [rax - 'A']
    cmp edx, 25
    ja .lower
    add al, 32
.lower:
    mov [rdi + rcx], al
    inc ecx
    jmp .name_char
.named:
    mov byte [rdi + rcx], 0
    call html_tag_kind              ; eax = kind
    mov r15d, eax
    cmp r15d, HTML_K_LINK
    jne .attrs
    test r14d, r14d
    jnz .attrs
    call html_href                  ; takes the attributes, up to ">"
.attrs:
    cmp rbx, r12                    ; skip the rest of the tag
    jae .apply
    mov al, [rbx]
    inc rbx
    cmp al, '>'
    jne .attrs
.apply:
    mov edi, r15d
    mov esi, r14d
    jmp html_apply

; name: html_tag_kind
; in:   html_tag_name
; out:  eax = its HTML_K_* kind, 0 for tags with no effect
; clobbers: rax, rcx, rdx, rsi, rdi
html_tag_kind:
    lea rdx, [rel html_tags]
.next:
    movzx eax, byte [rdx]
    test eax, eax
    jz .done
    lea rsi, [rdx + 1]
    lea rdi, [rel html_tag_name]
.cmp:
    mov cl, [rsi]
    cmp cl, [rdi]
    jne .skip
    inc rsi
    inc rdi
    test cl, cl
    jnz .cmp
    ret
.skip:
    inc rsi
    cmp byte [rsi - 1], 0
    jne .skip
    mov rdx, rsi
    jmp .next
.done:
    ret

; name: html_href
; in:   rbx = in an <a> tag, r12 = end
; out:  its href stored as the next link and html_style_now set to links;
;       rbx at the ">" or wherever the attributes ended
; clobbers: rax, rcx, rdx, rdi
html_href:
    cmp rbx, r12
    jae .done
    cmp byte [rbx], '>'
    je .done
    lea rax, [rbx + 5]
    cmp rax, r12
    ja .done
    mov eax, [rbx]
    or eax, 0x20202020
    cmp eax, 'href'
    jne .skip
    cmp byte [rbx + 4], '='
    je .value
.skip:
    inc rbx
    jmp html_href
.value:
    add rbx, 5
    xor edx, edx                    ; edx = the quote, or 0
    cmp rbx, r12
    jae .done
    mov al, [rbx]
    cmp al, '"'
    je .quoted
    cmp al, 39
    jne .copy
.quoted:
    mov dl, al
    inc rbx
.copy:
    mov eax, [rel html_link_count]
    cmp eax, HTML_LINKS
    jae .done
    shl eax, 8                      ; HTML_HREF_MAX bytes a link
    lea rdi, [rel html_links]
    add rdi, rax
    xor ecx, ecx
.char:
    cmp rbx, r12
    jae .stored
    mov al, [rbx]
    test dl, dl
    jz .bare
    cmp al, dl
    je .stored_quote
    jmp .keep
.bare:
    cmp al, '>'
    je .stored
    cmp al, ' '
    jbe .stored
.keep:
    inc rbx
    cmp ecx, HTML_HREF_MAX - 1
    jae .char
    mov [rdi + rcx], al
    inc ecx
    jmp .char
.stored_quote:
    inc rbx
.stored:
    mov byte [rdi + rcx], 0
    inc dword [rel html_link_count]
    mov al, [rel html_style_now]
    mov [rel html_style_out], al    ; restored after the link
    mov byte [rel html_style_now], HTML_LINK
.done:
    ret

; name: html_apply
; in:   edi = tag kind, esi = 1 if closing; the html_layout registers
; out:  the layout state changed for that tag
; clobbers: caller-saved except the html_layout registers
html_apply:
    cmp edi, HTML_K_BLOCK
    je .block
    cmp edi, HTML_K_PARA
    je .para
    cmp edi, HTML_K_HEAD
    je .heading
    cmp edi, HTML_K_TITLE
    je .title
    cmp edi, HTML_K_SKIP
    je .skip
    cmp edi, HTML_K_LINK
    je .link
    cmp edi, HTML_K_ITEM
    je .item
    cmp edi, HTML_K_RULE
    je .rule
    ret
.block:
    xor esi, esi
    jmp html_break
.para:
    mov esi, 1
    jmp html_break
.heading:
    push rsi
    mov esi, 1
    call html_break
    pop rsi
    mov byte [rel html_style_now], HTML_HEADING
    test esi, esi
    jz .done
    mov byte [rel html_style_now], HTML_TEXT
    ret
.title:
    xor eax, eax
    test esi, esi
    sete al
    mov [rel html_in_title], al
    mov byte [rel html_space], 0
    ret
.link:
    test esi, esi
    jz .done
    cmp byte [rel html_style_now], HTML_LINK
    jne .done
    mov byte [rel html_style_now], HTML_MARK
    mov edi, '['
    call html_char
    mov edi, [rel html_link_count]
    call html_number
    mov edi, ']'
    call html_char
    mov al, [rel html_style_out]
    mov [rel html_style_now], al
    ret
.item:
    test esi, esi
    jnz .done
    xor esi, esi
    call html_break
    mov edi, '*'
    call html_char
    call html_flush
    mov byte [rel html_space], 1
    ret
.rule:
    xor esi, esi
    call html_break
    mov ecx, r13d
.dash:
    push rcx
    mov edi, '-'
    call html_char
    pop rcx
    dec ecx
    jnz .dash
    xor esi, esi
    jmp html_break
.skip:
    test esi, esi                   ; jump to the matching close tag
    jnz .done
    lea rsi, [rel html_tag_name]
.find:
    lea rax, [rbx + 2]
    cmp rax, r12
    jae .lost
    cmp word [rbx], '</'
    jne .find_next
    lea rdi, [rbx + 2]
    mov rdx, rsi
.same:
    mov cl, [rdx]
    test cl, cl
    jz .found
    cmp rdi, r12
    jae .lost
    mov al, [rdi]
    or al, 0x20
    cmp al, cl
    jne .find_next
    inc rdi
    inc rdx
    jmp .same
.find_next:
    inc rbx
    jmp .find
.found:
    mov rbx, rdi
.close_end:
    cmp rbx, r12
    jae .done
    inc rbx
    cmp byte [rbx - 1], '>'
    jne .close_end
.done:
    ret
.lost:
    mov rbx, r12
    ret

; name: html_number
; in:   edi = number
; out:  its decimal digits added to the current word
; clobbers: rax, rcx, rdx, rdi
html_number:
    mov eax, edi
    xor ecx, ecx
.split:
    xor edx, edx
    mov edi, 10
    div edi
    push rdx
    inc ecx
    test eax, eax
    jnz .split
.emit:
    pop rdi
    add edi, '0'
    push rcx
    call html_char
    pop rcx
    dec ecx
    jnz .emit
    ret

; name: cmd_view
; in:   rdi = URL
; out:  the page fetched, laid out HTML_VIEW_COLS wide and printed with its
;       title and link list
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
    lea rdi, [rel html_msg_title]
    call kputs
    lea rdi, [rel html_title]
    call kputs
    mov edi, 10
    call kputc
    xor ebx, ebx
.line:
    cmp ebx, [rel html_lines]
    jae .links
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
.links:
    xor ebx, ebx
.link:
    cmp ebx, [rel html_link_count]
    jae .done
    mov edi, '['
    call kputc
    lea edi, [rbx + 1]
    call [rel jt_kput_dec]
    lea rdi, [rel html_msg_link]
    call kputs
    mov eax, ebx
    shl eax, 8
    lea rdi, [rel html_links]
    add rdi, rax
    call kputs
    mov edi, 10
    call kputc
    inc ebx
    jmp .link
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

html_msg_title db "[view] ", 0
html_msg_link  db "] ", 0

; kind, then the name; a 0 kind ends the table
html_tags:
    db HTML_K_BLOCK, "br", 0, HTML_K_BLOCK, "div", 0, HTML_K_BLOCK, "tr", 0
    db HTML_K_BLOCK, "table", 0, HTML_K_BLOCK, "ul", 0, HTML_K_BLOCK, "ol", 0
    db HTML_K_ITEM, "li", 0, HTML_K_RULE, "hr", 0, HTML_K_BLOCK, "dd", 0
    db HTML_K_BLOCK, "section", 0, HTML_K_BLOCK, "header", 0
    db HTML_K_BLOCK, "footer", 0, HTML_K_BLOCK, "nav", 0, HTML_K_BLOCK, "main", 0
    db HTML_K_BLOCK, "article", 0, HTML_K_BLOCK, "form", 0, HTML_K_BLOCK, "dt", 0
    db HTML_K_PARA, "p", 0, HTML_K_PARA, "blockquote", 0, HTML_K_PARA, "pre", 0
    db HTML_K_HEAD, "h1", 0, HTML_K_HEAD, "h2", 0, HTML_K_HEAD, "h3", 0
    db HTML_K_HEAD, "h4", 0, HTML_K_HEAD, "h5", 0, HTML_K_HEAD, "h6", 0
    db HTML_K_TITLE, "title", 0, HTML_K_SKIP, "script", 0, HTML_K_SKIP, "style", 0
    db HTML_K_SKIP, "svg", 0, HTML_K_SKIP, "noscript", 0, HTML_K_LINK, "a", 0
    db 0

; character, then the name with its ';'; a 0 character ends the table
html_entities:
    db "&", "amp;", "<", "lt;", ">", "gt;", '"', "quot;", 39, "apos;", " ", "nbsp;"
    db 0xa9, "copy;", 0

section .bss
alignb 8
html_lines      resd 1
html_col        resd 1
html_word_len   resd 1
html_title_len  resd 1
html_link_count resd 1
html_space      resb 1
html_style_now  resb 1
html_style_out  resb 1
html_in_title   resb 1
html_tag_name   resb HTML_TAG_MAX
html_word       resb HTML_WORD_MAX
html_word_style resb HTML_WORD_MAX
html_title      resb HTML_TITLE_MAX
alignb 4096
html_text       resb HTML_LINES * HTML_COLS
html_style      resb HTML_LINES * HTML_COLS
html_links      resb HTML_LINKS * HTML_HREF_MAX
section .text
