; Inspect mode, the click: dim what the clicked pixel's call chain did not
; draw and show that chain in a panel beside the pointer (glass/inspect.asm).

INSP_PANEL_W equ 304                ; 36 characters and the margins
INSP_FG      equ 0x00eceff4

; name: insp_dim
; in:   edi = a chain id
; out:  the saved screen put back with every pixel that chain did not draw
;       at half brightness
; clobbers: caller-saved
insp_dim:
    pushfq
    cli
    call cursor_off
    mov rsi, [rel insp_screen]
    mov r8, [rel insp_map]
    mov r9, [rel fb_base]
    xor edx, edx
.row:
    cmp rdx, [rel fb_height]
    jae .done
    xor ecx, ecx
.px:
    mov eax, [rsi]
    cmp [r8], edi
    je .put
    shr eax, 1
    and eax, 0x7f7f7f
.put:
    mov [r9 + rcx * 4], eax
    add rsi, 4
    add r8, 4
    inc rcx
    cmp rcx, [rel fb_width]
    jb .px
    add r9, [rel fb_pitch]
    inc rdx
    jmp .row
.done:
    call cursor_on
    popfq
    ret

; name: insp_show
; in:   mouse_x, mouse_y = the clicked pixel
; out:  the screen dimmed around what drew it, and its chain in a panel
; clobbers: caller-saved
insp_show:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov eax, [rel mouse_y]
    imul rax, [rel fb_width]
    mov ecx, [rel mouse_x]
    add rax, rcx
    mov rcx, [rel insp_map]
    mov ebx, [rcx + rax * 4]        ; chain id
    mov edi, ebx
    call insp_dim
    call insp_bar
    xor r15d, r15d                  ; lines
    test ebx, ebx
    jz .nothing
    lea eax, [rbx - 1]
    shl rax, 6
    add rax, [rel prov_chains]
    mov rbx, rax
    mov r15d, [rbx + PROV_COUNT]
.nothing:
    lea r13, [r15 + 1]              ; panel height: the lines, 16 px each,
    shl r13, 4                      ; and 16 px of margin above and below
    add r13, 32
    mov r12d, [rel mouse_x]         ; panel left, its edge kept on screen
    add r12, 16
    lea rax, [r12 + INSP_PANEL_W]
    cmp rax, [rel fb_width]
    jb .left
    mov r12d, [rel mouse_x]
    sub r12, INSP_PANEL_W + 16
    ja .left
    mov r12d, 1
.left:
    mov r14d, [rel mouse_y]         ; panel top
    add r14, 16
    lea rax, [r14 + r13]
    cmp rax, [rel fb_height]
    jb .top
    mov r14, [rel fb_height]
    sub r14, r13
    dec r14
.top:                               ; on the character grid, the edge on screen
    and r12, -8
    jnz .grid_y
    mov r12d, 8
.grid_y:
    and r14, -16
    jnz .draw
    mov r14d, 16
.draw:
    lea rdi, [r12 - 1]
    lea rsi, [r14 - 1]
    mov edx, INSP_PANEL_W + 2
    lea rcx, [r13 + 2]
    mov r8d, INSP_EDGE
    call fb_fill_rect
    mov rdi, r12
    mov rsi, r14
    mov edx, INSP_PANEL_W
    mov rcx, r13
    mov r8d, INSP_BG
    call fb_fill_rect
    add r12, 8
    add r14, 16
    test r15d, r15d
    jnz .task
    lea rsi, [rel insp_msg_nothing]
    call insp_start
    jmp .last
.task:
    lea rsi, [rel insp_msg_task]
    call insp_start
    mov edi, [rbx + PROV_TASK]
    call insp_dec
    lea rsi, [rel insp_msg_space]
    call insp_cat
    mov eax, [rbx + PROV_TASK]
    imul eax, TASK_SIZE
    lea rsi, [rel sched_tasks + TASK_NAME]
    add rsi, rax
    call insp_cat
    mov ecx, INSP_EDGE
    call insp_line
    xor r13d, r13d
.frame:
    cmp r13d, r15d
    jae .done
    mov rdi, [rbx + PROV_FRAMES + r13 * 8]
    call prov_function
    jc .next
    mov rdi, [rbx + PROV_FRAMES + r13 * 8]
    sub rdi, rax
    push rdi
    push rdx
    lea rsi, [rel insp_msg_indent]
    call insp_start
    pop rsi
    add rsi, SYM_NAME
    call insp_cat
    lea rsi, [rel insp_msg_plus]
    call insp_cat
    pop rdi
    call insp_dec
.last:
    mov ecx, INSP_FG
    call insp_line
.next:
    inc r13d
    jmp .frame
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: insp_line
; in:   ecx = colour, insp_text = the line, r12 = x, r14 = y
; out:  the line drawn there and r14 moved to the next one
; clobbers: caller-saved but r12, r14
insp_line:
    sub rsp, 8
    mov rdi, r12
    mov rsi, r14
    lea rdx, [rel insp_text]
    mov r8d, INSP_BG
    call dt_text
    add r14, 16
    add rsp, 8
    ret

; name: insp_start
; in:   rsi = string
; out:  insp_text = that string, at most 36 characters
; clobbers: rax, rcx, rdx, rsi
insp_start:
    mov qword [rel insp_len], 0

; name: insp_cat
; in:   rsi = string
; out:  the string appended to insp_text, which stops at 36 characters
; clobbers: rax, rcx, rdx, rsi
insp_cat:
    mov rcx, [rel insp_len]
    lea rax, [rel insp_text]
.char:
    cmp ecx, 36
    jae .end
    mov dl, [rsi]
    test dl, dl
    jz .end
    mov [rax + rcx], dl
    inc rsi
    inc ecx
    jmp .char
.end:
    mov byte [rax + rcx], 0
    mov [rel insp_len], rcx
    ret

; name: insp_dec
; in:   rdi = unsigned value
; out:  its decimal digits appended to insp_text
; clobbers: rax, rcx, rdx, rsi
insp_dec:
    sub rsp, 40
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rax, rdi
    mov ecx, 10
.digit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit
    call insp_cat
    add rsp, 40
    ret

insp_msg_nothing db "nothing recorded here", 0
insp_msg_task    db "drawn by task ", 0
insp_msg_space   db " ", 0
insp_msg_indent  db "  ", 0
insp_msg_plus    db "+", 0

section .bss
alignb 8
insp_len    resq 1
insp_text   resb 40
section .text
