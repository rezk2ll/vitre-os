; Editor text buffer: one flat array with a cursor offset. Inserting and
; deleting move the tail; modules are small enough that this stays instant.

ED_PAGES equ 16                     ; largest module the editor takes

; name: ed_insert
; in:   dil = byte
; out:  byte inserted at the cursor, cursor after it; ed_status set if full
; clobbers: rax, rcx, rsi, rdi
ed_insert:
    mov rax, [rel ed_len]
    cmp rax, ED_PAGES * PAGE_SIZE
    jae .full
    push rdi
    mov rcx, rax
    sub rcx, [rel ed_cur]
    mov rsi, [rel ed_buf]
    lea rsi, [rsi + rax - 1]
    lea rdi, [rsi + 1]
    std                             ; overlapping move to the right: copy backwards
    rep movsb
    cld
    pop rdi
    mov rax, [rel ed_buf]
    add rax, [rel ed_cur]
    mov [rax], dil
    inc qword [rel ed_cur]
    inc qword [rel ed_len]
    mov byte [rel ed_dirty], 1
    ret
.full:
    lea rax, [rel ed_msg_full]
    mov [rel ed_status], rax
    ret

; name: ed_delete
; in:   ed_cur < ed_len
; out:  byte at the cursor removed
; clobbers: rcx, rsi, rdi
ed_delete:
    mov rcx, [rel ed_len]
    sub rcx, [rel ed_cur]
    dec rcx
    mov rdi, [rel ed_buf]
    add rdi, [rel ed_cur]
    lea rsi, [rdi + 1]
    rep movsb
    dec qword [rel ed_len]
    mov byte [rel ed_dirty], 1
    ret

; name: ed_line_start
; in:   rdi = offset
; out:  rax = offset of the start of its line
; clobbers: rcx
ed_line_start:
    mov rax, rdi
    mov rcx, [rel ed_buf]
.back:
    test rax, rax
    jz .done
    cmp byte [rcx + rax - 1], 10
    je .done
    dec rax
    jmp .back
.done:
    ret

; name: ed_line_end
; in:   rdi = offset
; out:  rax = offset of the newline ending its line, or ed_len
; clobbers: rcx
ed_line_end:
    mov rax, rdi
    mov rcx, [rel ed_buf]
.forward:
    cmp rax, [rel ed_len]
    jae .done
    cmp byte [rcx + rax], 10
    je .done
    inc rax
    jmp .forward
.done:
    ret

; name: ed_up
; in:   none
; out:  cursor on the previous line, same column or its end
; clobbers: rax, rcx, rdi, r8, r9
ed_up:
    mov rdi, [rel ed_cur]
    call ed_line_start
    test rax, rax
    jz .done
    mov r8, rax
    mov r9, [rel ed_cur]
    sub r9, r8                      ; column
    lea rdi, [r8 - 1]
    call ed_line_start
    add rax, r9
    lea rcx, [r8 - 1]
    cmp rax, rcx
    cmova rax, rcx
    mov [rel ed_cur], rax
.done:
    ret

; name: ed_down
; in:   none
; out:  cursor on the next line, same column or its end
; clobbers: rax, rcx, rdi, r8, r9
ed_down:
    mov rdi, [rel ed_cur]
    call ed_line_start
    mov r9, [rel ed_cur]
    sub r9, rax                     ; column
    mov rdi, [rel ed_cur]
    call ed_line_end
    cmp rax, [rel ed_len]
    jae .done
    lea rdi, [rax + 1]
    lea r8, [rdi + r9]
    call ed_line_end
    cmp r8, rax
    cmova r8, rax
    mov [rel ed_cur], r8
.done:
    ret

; name: ed_scroll_to_cursor
; in:   none
; out:  ed_top moved so the cursor line is one of the ed_rows shown
; clobbers: rax, rcx, rdi, r8, r9
ed_scroll_to_cursor:
    mov rdi, [rel ed_cur]
    call ed_line_start
    mov r8, rax
    cmp r8, [rel ed_top]
    jae .below
    mov [rel ed_top], r8
    ret
.below:
    xor r9d, r9d                    ; lines from the top line to the cursor's
    mov rdi, [rel ed_top]
.count:
    cmp rdi, r8
    jae .counted
    call ed_line_end
    lea rdi, [rax + 1]
    inc r9
    jmp .count
.counted:
    cmp r9, [rel ed_rows]
    jb .done
    mov rdi, [rel ed_top]
    call ed_line_end
    inc rax
    mov [rel ed_top], rax
    dec r9
    jmp .counted
.done:
    ret

ed_msg_full db "buffer full", 0

section .bss
alignb 8
ed_buf    resq 1
ed_len    resq 1
ed_cur    resq 1                    ; cursor offset in the text
ed_top    resq 1                    ; offset of the first line on screen
ed_rows   resq 1                    ; text rows; the status line is below
ed_cols   resq 1
ed_path   resq 1
ed_status resq 1                    ; message for the status line, or 0
ed_dirty  resb 1
section .text
