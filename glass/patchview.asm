; Glass patch view: `glass patch` lists the jump table slots the live patch
; swapped, and shows the selected function's old and new code side by side.

GV_LIST_MAX equ 8
GV_CODE_ROW equ 2 + GV_LIST_MAX + 2

; name: gv_run
; in:   none
; out:  the view ran until q or Esc; the screen is cleared
; clobbers: caller-saved
gv_run:
    push rbx
    cmp qword [rel patch_count], 0
    je .none
    cmp byte [rel console_ready], 0
    je .none
    xor ebx, ebx                    ; selected entry
    lea rdi, [rel kernel_console]
    call console_clear
.frame:
    mov edi, ebx
    call gv_render
    call kbd_getc
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    cmp eax, KEY_UP
    jne .down
    test ebx, ebx
    jz .frame
    dec ebx
    jmp .frame
.down:
    cmp eax, KEY_DOWN
    jne .frame
    lea eax, [rbx + 1]
    cmp rax, [rel patch_count]
    jae .frame
    cmp eax, GV_LIST_MAX
    jae .frame
    mov ebx, eax
    jmp .frame
.quit:
    call shell_clear_screen
    jmp .done
.none:
    lea rdi, [rel gv_msg_none]
    call kputs
.done:
    pop rbx
    ret

; name: gv_render
; in:   edi = selected entry
; out:  title, the swapped slots and both code columns drawn
; clobbers: caller-saved
gv_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    xor esi, esi
    lea rdx, [rel gv_msg_title]
    call gl_bar
    mov edi, 1
    mov esi, 1
    lea rdx, [rel gv_msg_slots]
    call gl_header
    mov r13, [rel patch_count]
    cmp r13, GV_LIST_MAX
    jbe .list
    mov r13d, GV_LIST_MAX
.list:
    xor ebx, ebx
.entry:
    imul r14, rbx, PATCH_ENTRY
    lea rax, [rel patch_entries]
    add r14, rax
    lea rax, [rel gl_line]          ; "jt <slot>  <new> <name>  was <old>"
    mov [rel dis_out], rax
    lea rdi, [rel gv_msg_jt]
    call dis_s
    mov rdi, [r14 + PATCH_SLOT]
    call dis_hex
    lea rdi, [rel gv_msg_gap]
    call dis_s
    mov rdi, [r14 + PATCH_NEW]
    call dis_target
    lea rdi, [rel gv_msg_was]
    call dis_s
    mov rdi, [r14 + PATCH_OLD]
    call dis_hex
    mov rax, [rel dis_out]
    mov byte [rax], 0
    mov r15d, COLOR_BG
    cmp ebx, r12d
    jne .row
    mov r15d, GL_RIP_BG
.row:
    xor edi, edi
    lea esi, [rbx + 2]
    mov edx, 1000
    mov ecx, r15d
    call gl_fill
    mov edi, 1
    lea esi, [rbx + 2]
    lea rdx, [rel gl_line]
    mov ecx, COLOR_FG
    mov r8d, r15d
    call gl_text
    inc ebx
    cmp ebx, r13d
    jb .entry
    mov edi, 1
    mov esi, GV_CODE_ROW - 1
    lea rdx, [rel gv_msg_old]
    call gl_header
    mov rdi, [rel kernel_console + CON_COLS]
    shr edi, 1
    inc edi
    mov esi, GV_CODE_ROW - 1
    lea rdx, [rel gv_msg_new]
    call gl_header
    imul r14d, r12d, PATCH_ENTRY
    lea rax, [rel patch_entries]
    add r14, rax
    mov r15, [r14 + PATCH_NEW]
    mov r14, [r14 + PATCH_OLD]
    mov ebx, GV_CODE_ROW
.line:
    mov rax, [rel kernel_console + CON_ROWS]
    dec eax
    cmp ebx, eax
    jae .keys
    xor edi, edi
    mov esi, ebx
    mov edx, 1000
    mov ecx, COLOR_BG
    call gl_fill
    mov edi, 1
    mov esi, ebx
    mov rdx, r14
    call gv_code_line
    add r14, rax
    mov rdi, [rel kernel_console + CON_COLS]    ; the old column may run long
    shr edi, 1
    mov esi, ebx
    mov edx, 1000
    mov ecx, COLOR_BG
    call gl_fill
    mov rdi, [rel kernel_console + CON_COLS]
    shr edi, 1
    inc edi
    mov esi, ebx
    mov rdx, r15
    call gv_code_line
    add r15, rax
    inc ebx
    jmp .line
.keys:
    mov rsi, [rel kernel_console + CON_ROWS]
    dec esi
    lea rdx, [rel gv_msg_keys]
    call gl_bar
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: gv_code_line
; in:   edi = column, esi = row, rdx = instruction address
; out:  its address and text drawn; rax = its length
; clobbers: caller-saved
gv_code_line:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov ecx, 8
    mov r8d, GL_DIM
    call gl_hex
    mov rdi, rbx
    lea rsi, [rel gl_line]
    call dis_one
    mov rbx, rax
    lea edi, [r12 + 10]
    mov esi, r13d
    lea rdx, [rel gl_line]
    mov ecx, COLOR_FG
    mov r8d, COLOR_BG
    call gl_text
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

gv_word      db "patch", 0
gv_msg_title db "glass  live patch", 0
gv_msg_slots db "jump table slots swapped", 0
gv_msg_old   db "old code", 0
gv_msg_new   db "new code", 0
gv_msg_jt    db "jt ", 0
gv_msg_gap   db "  ", 0
gv_msg_was   db "  was ", 0
gv_msg_keys  db "up/down pick a function   q quit", 0
gv_msg_none  db "[glass] no live patch, or no screen", 10, 0
