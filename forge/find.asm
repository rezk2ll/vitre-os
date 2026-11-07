; Editor search: Ctrl+F reads a string on the status line and jumps to it.

ED_QUERY_MAX equ 40

; name: ed_find
; in:   none
; out:  reads a search string on the status line, then moves the cursor to
;       its next occurrence after the cursor, wrapping at the end
; clobbers: caller-saved
ed_find:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx
.read:
    lea rax, [rel ed_query]
    mov byte [rax + rbx], 0
    lea rax, [rel ed_query_line]
    mov [rel ed_status], rax
    call ed_render
    call kbd_getc
    cmp eax, 10
    je .search
    cmp eax, KEY_ESC
    je .cancel
    cmp eax, 8
    je .erase
    cmp eax, ' '
    jb .read
    lea ecx, [rax - 0x80]
    cmp ecx, 0x20
    jb .read
    cmp ebx, ED_QUERY_MAX
    jae .read
    lea rcx, [rel ed_query]
    mov [rcx + rbx], al
    inc ebx
    jmp .read
.erase:
    test ebx, ebx
    jz .read
    dec ebx
    jmp .read
.search:
    test ebx, ebx
    jz .cancel
    mov r12, [rel ed_cur]           ; start one byte on, so "find" repeats
    xor ecx, ecx                    ; bytes tried
.try:
    inc r12
    cmp r12, [rel ed_len]
    jb .compare
    xor r12d, r12d
.compare:
    cmp rcx, [rel ed_len]
    ja .not_found
    inc rcx
    mov rsi, [rel ed_buf]
    add rsi, r12
    lea rax, [r12 + rbx]
    cmp rax, [rel ed_len]
    ja .try
    xor edx, edx
    lea rdi, [rel ed_query]
.char:
    mov al, [rdi + rdx]
    cmp al, [rsi + rdx]
    jne .try
    inc edx
    cmp edx, ebx
    jb .char
    mov [rel ed_cur], r12
.cancel:
    mov qword [rel ed_status], 0
    jmp .done
.not_found:
    lea rax, [rel ed_msg_not_found]
    mov [rel ed_status], rax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

ed_msg_not_found db "  not found", 0
ed_query_line    db "  find: "
ed_query         times ED_QUERY_MAX + 1 db 0
