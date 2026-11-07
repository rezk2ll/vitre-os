; Forge editor: full-screen editing of one module of the source area.
; Ctrl+S stores the text back into the source area, where `patch` and
; `save` pick it up. Ctrl+Q or Esc leaves. A click puts the cursor on the
; character under the pointer; the wheel moves it three lines a notch.

ED_WHEEL_LINES equ 3

ED_KEY_FIND  equ 6                  ; Ctrl+F
ED_KEY_QUIT  equ 17                 ; Ctrl+Q
ED_KEY_STORE equ 19                 ; Ctrl+S
ED_TAB       equ 4                  ; spaces a Tab inserts

; name: cmd_edit
; in:   rdi = module path
; out:  the editor ran until Ctrl+Q; the screen is cleared after it
; clobbers: caller-saved
cmd_edit:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    cmp byte [rbx], 0
    je .usage
    lea rdi, [rel ed_msg_prefix]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel forge_msg_colon]
    call kputs
    cmp byte [rel console_ready], 0
    je .no_screen
    mov rdi, rbx
    call src_find
    jnc .found
    mov rdi, rbx
    call src_add
    jc .missing
    mov rdi, rbx
    call src_find
.found:
    cmp rdx, ED_PAGES * PAGE_SIZE
    ja .too_big
    mov r12, rax
    mov [rel ed_len], rdx
    mov edi, ED_PAGES
    call page_alloc
    jc .no_memory
    mov [rel ed_buf], rax
    mov rdi, rax
    mov rsi, r12
    mov rcx, [rel ed_len]
    rep movsb
    lea rdi, [rel ed_msg_opened]
    call kputs
    mov [rel ed_path], rbx
    xor eax, eax
    mov [rel ed_cur], rax
    mov [rel ed_top], rax
    mov [rel ed_status], rax
    mov byte [rel ed_dirty], 0
    mov rax, [rel kernel_console + CON_COLS]
    mov [rel ed_cols], rax
    mov rax, [rel kernel_console + CON_ROWS]
    dec rax
    mov [rel ed_rows], rax
    call mouse_click                ; forget a click made before the editor
    call mouse_scroll
.key:
    call ed_render
    call ed_input
    test eax, eax
    jz .key                         ; the mouse moved the cursor
    mov edi, eax
    call ed_key
    jnc .key
    mov rdi, [rel ed_buf]
    mov esi, ED_PAGES
    call page_free
    call shell_clear_screen
    jmp .done
.usage:
    lea rdi, [rel ed_msg_usage]
    jmp .print
.no_screen:
    lea rdi, [rel ed_msg_no_screen]
    jmp .print
.missing:
    lea rdi, [rel patch_msg_missing]
    jmp .print
.too_big:
    lea rdi, [rel ed_msg_too_big]
    jmp .print
.no_memory:
    lea rdi, [rel forge_msg_no_memory]
.print:
    call kputs
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: ed_input
; in:   none
; out:  eax = the next key, or 0 once a click or the wheel moved the cursor
; clobbers: caller-saved
ed_input:
    push rbx
.wait:
    call kbd_poll
    jnz .ret
    call mouse_click
    jc .wheel
    call ed_click
    jnc .moved
.wheel:
    call mouse_scroll
    test eax, eax
    jnz .scroll
    sti
    hlt                             ; any IRQ, the mouse's included, wakes it
    jmp .wait
.scroll:
    mov ebx, eax
    js .up                          ; flags from the test above
    imul ebx, ebx, ED_WHEEL_LINES
.down:
    call ed_down
    dec ebx
    jnz .down
    jmp .moved
.up:
    neg ebx
    imul ebx, ebx, ED_WHEEL_LINES
.up_line:
    call ed_up
    dec ebx
    jnz .up_line
.moved:
    xor eax, eax
.ret:
    pop rbx
    ret

; name: ed_click
; in:   ed_top as last drawn
; out:  ed_cur on the character under the pointer, or the end of its line;
;       CF=1 if the pointer is on the status line
; clobbers: rax, rcx, rdx, rdi, rsi
ed_click:
    mov eax, [rel mouse_y]
    shr eax, 4
    cmp rax, [rel ed_rows]
    jae .out
    mov esi, eax                    ; rows below the top line
    mov rdi, [rel ed_top]
.row:
    test esi, esi
    jz .line
    call ed_line_end
    cmp rax, [rel ed_len]
    jae .line_of_rax                ; below the last line: stay on it
    lea rdi, [rax + 1]
    dec esi
    jmp .row
.line_of_rax:
    mov rdi, rax
    call ed_line_start
    mov rdi, rax
.line:
    mov edx, [rel mouse_x]
    shr edx, 3
    add rdx, rdi
    call ed_line_end
    cmp rdx, rax
    cmova rdx, rax
    mov [rel ed_cur], rdx
    clc
    ret
.out:
    stc
    ret

; name: ed_key
; in:   edi = key from kbd_getc
; out:  key applied to the text; CF=1 to leave the editor
; clobbers: caller-saved
ed_key:
    push rbx
    mov ebx, edi
    mov qword [rel ed_status], 0
    cmp ebx, ED_KEY_QUIT
    je .quit
    cmp ebx, KEY_ESC
    je .quit
    cmp ebx, ED_KEY_STORE
    je .store
    cmp ebx, ED_KEY_FIND
    je .find
    cmp ebx, 10
    je .insert
    cmp ebx, 9
    je .tab
    cmp ebx, 8
    je .backspace
    cmp ebx, KEY_DEL
    je .delete
    cmp ebx, KEY_LEFT
    je .left
    cmp ebx, KEY_RIGHT
    je .right
    cmp ebx, KEY_UP
    je .up
    cmp ebx, KEY_DOWN
    je .down
    cmp ebx, KEY_HOME
    je .home
    cmp ebx, KEY_END
    je .end
    cmp ebx, KEY_PGUP
    je .page_up
    cmp ebx, KEY_PGDN
    je .page_down
    cmp ebx, ' '
    jb .done
    cmp ebx, 0x7f
    je .done
    lea eax, [rbx - 0x80]           ; KEY_* codes have no character
    cmp eax, 0x20
    jb .done
.insert:
    mov edi, ebx
    call ed_insert
    jmp .done
.tab:
    mov ebx, ED_TAB
.space:
    mov edi, ' '
    call ed_insert
    dec ebx
    jnz .space
    jmp .done
.backspace:
    cmp qword [rel ed_cur], 0
    je .done
    dec qword [rel ed_cur]
    call ed_delete
    jmp .done
.delete:
    mov rax, [rel ed_cur]
    cmp rax, [rel ed_len]
    jae .done
    call ed_delete
    jmp .done
.left:
    cmp qword [rel ed_cur], 0
    je .done
    dec qword [rel ed_cur]
    jmp .done
.right:
    mov rax, [rel ed_cur]
    cmp rax, [rel ed_len]
    jae .done
    inc qword [rel ed_cur]
    jmp .done
.up:
    call ed_up
    jmp .done
.down:
    call ed_down
    jmp .done
.home:
    mov rdi, [rel ed_cur]
    call ed_line_start
    mov [rel ed_cur], rax
    jmp .done
.end:
    mov rdi, [rel ed_cur]
    call ed_line_end
    mov [rel ed_cur], rax
    jmp .done
.page_up:
    mov rbx, [rel ed_rows]
.page_up_line:
    call ed_up
    dec rbx
    jnz .page_up_line
    jmp .done
.page_down:
    mov rbx, [rel ed_rows]
.page_down_line:
    call ed_down
    dec rbx
    jnz .page_down_line
    jmp .done
.store:
    call ed_store
    jmp .done
.find:
    call ed_find
.done:
    pop rbx
    clc
    ret
.quit:
    pop rbx
    stc
    ret

; name: ed_store
; in:   none
; out:  the text replaces the module in the source area; the log says so
; clobbers: caller-saved
ed_store:
    sub rsp, 8
    mov rdi, [rel ed_path]
    mov rsi, [rel ed_buf]
    mov rdx, [rel ed_len]
    call src_replace
    lea rax, [rel ed_msg_store_failed]
    jc .status
    mov byte [rel ed_dirty], 0
    lea rdi, [rel ed_msg_prefix]
    call kputs
    mov rdi, [rel ed_path]
    call kputs
    lea rdi, [rel ed_msg_stored]
    call kputs
    mov rdi, [rel ed_len]
    call [rel jt_kput_dec]
    lea rdi, [rel src_msg_bytes]
    call kputs
    mov rdi, [rel ed_path]
    call src_find
    lea rax, [rel ed_msg_status_stored]
    test dword [rcx + SRC_DIR_FLAGS], SRC_FILE
    jz .status
    lea rax, [rel ed_msg_status_file]
.status:
    mov [rel ed_status], rax
    add rsp, 8
    ret

ed_msg_prefix        db "[edit] ", 0
ed_msg_opened        db "opened", 10, 0
ed_msg_stored        db ": stored ", 0
ed_msg_usage         db "usage: edit <file>", 10, 0
ed_msg_no_screen     db "no screen", 10, 0
ed_msg_too_big       db "too big for the editor", 10, 0
ed_msg_store_failed  db "  store failed: source area full", 0
ed_msg_status_stored db "  stored, patch it to run it", 0
ed_msg_status_file   db "  stored, save writes it to disk", 0
