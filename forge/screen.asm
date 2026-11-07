; Editor drawing: the text rows and the inverted status line, straight
; to the framebuffer on the 8x16 grid.

; name: ed_render
; in:   none
; out:  the visible lines and the status line drawn; the cursor cell is
;       drawn inverted
; clobbers: caller-saved
ed_render:
    push rbx
    push r12
    push r13
    call ed_scroll_to_cursor
    mov rbx, [rel ed_top]
    xor r12d, r12d
.row:
    cmp r12, [rel ed_rows]
    jae .status
    xor r13d, r13d
.cell:
    cmp r13, [rel ed_cols]
    jae .skip_rest
    cmp rbx, [rel ed_len]
    jae .line_end
    mov rax, [rel ed_buf]
    movzx edx, byte [rax + rbx]
    cmp edx, 10
    je .line_end
    call .draw
    inc rbx
    inc r13
    jmp .cell
.line_end:
    cmp rbx, [rel ed_cur]
    jne .fill
    mov edx, ' '
    call .draw
    inc r13
.fill:
    mov rdi, r13
    mov rsi, r12
    mov r8d, COLOR_BG
    call ed_fill_row
    jmp .next_line
.skip_rest:                         ; longer than the screen: cut
    mov rdi, rbx
    call ed_line_end
    mov rcx, [rel ed_cur]
    cmp rcx, rbx
    jb .cut
    cmp rcx, rax
    ja .cut
    push rax                        ; cursor in the cut part: show it at the edge
    sub rsp, 8
    mov rbx, rcx
    mov r13, [rel ed_cols]
    dec r13
    mov edx, ' '
    call .draw
    add rsp, 8
    pop rax
.cut:
    mov rbx, rax
.next_line:
    cmp rbx, [rel ed_len]
    jae .past_end
    inc rbx
    inc r12
    jmp .row
.past_end:
    mov rbx, [rel ed_len]           ; only the first row past the end can
    inc rbx                         ; hold the cursor
    inc r12
    jmp .row
.status:
    call ed_render_status
    pop r13
    pop r12
    pop rbx
    ret
.draw:                              ; edx at column r13, row r12, inverted at the cursor
    mov ecx, COLOR_FG
    mov r8d, COLOR_BG
    cmp rbx, [rel ed_cur]
    jne .glyph
    xchg ecx, r8d
.glyph:
    mov rdi, r13
    shl rdi, 3
    mov rsi, r12
    shl rsi, 4
    jmp fb_draw_glyph

; name: ed_fill_row
; in:   rdi = first column, rsi = row, r8d = colour
; out:  the row filled from that column to the right edge
; clobbers: rax, rcx, rdx, rdi, rsi, r9, r10
ed_fill_row:
    mov rdx, [rel ed_cols]
    sub rdx, rdi
    jbe .done
    shl rdx, 3
    shl rdi, 3
    shl rsi, 4
    mov ecx, FONT_HEIGHT
    jmp fb_fill_rect
.done:
    ret

; name: ed_render_status
; in:   none
; out:  inverted status line: path, line number, modified mark, then the
;       status message or the key help
; clobbers: caller-saved
ed_render_status:
    push rbx
    xor edi, edi
    mov rsi, [rel ed_rows]
    mov r8d, COLOR_FG
    call ed_fill_row
    xor ebx, ebx
    mov rdi, [rel ed_path]
    call ed_status_text
    lea rdi, [rel ed_msg_line]
    call ed_status_text
    mov rcx, [rel ed_cur]           ; line number: newlines before the cursor, + 1
    mov rsi, [rel ed_buf]
    mov eax, 1
.count:
    test rcx, rcx
    jz .counted
    dec rcx
    cmp byte [rsi + rcx], 10
    jne .count
    inc rax
    jmp .count
.counted:
    lea rdi, [rel ed_number + 20]
    mov byte [rdi], 0
    mov ecx, 10
.digit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .digit
    call ed_status_text
    cmp byte [rel ed_dirty], 0
    je .message
    lea rdi, [rel ed_msg_modified]
    call ed_status_text
.message:
    lea rdi, [rel ed_msg_help]
    cmp qword [rel ed_status], 0
    je .print
    mov rdi, [rel ed_status]
.print:
    call ed_status_text
    pop rbx
    ret

; name: ed_status_text
; in:   rdi = string, ebx = status line column
; out:  string drawn inverted on the status line, ebx past it
; clobbers: caller-saved but rbx
ed_status_text:
    push r12
    mov r12, rdi
.char:
    movzx edx, byte [r12]
    test edx, edx
    jz .done
    cmp rbx, [rel ed_cols]
    jae .done
    mov edi, ebx
    shl edi, 3
    mov rsi, [rel ed_rows]
    shl rsi, 4
    mov ecx, COLOR_BG
    mov r8d, COLOR_FG
    call fb_draw_glyph
    inc r12
    inc ebx
    jmp .char
.done:
    pop r12
    ret

ed_msg_line          db "  line ", 0
ed_msg_modified      db "  modified", 0
ed_msg_help          db "  ^S store  ^F find  ^Q quit", 0

section .bss
ed_number resb 21
section .text
