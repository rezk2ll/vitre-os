; Glass task view: `glass <task id>` takes the screen and shows the task's
; registers, the code around RIP, its stack and memory, redrawn ten times a
; second while it runs. Keys: p pause or resume, s step, f open the module
; under RIP in the editor, q or Esc leave.

GL_REFRESH_MS equ 100
GL_TITLE_BG   equ 0x003b4252

; name: cmd_glass
; in:   rdi = "<task id> [0xaddress|label]", the memory pane's address
;       (RIP by default), or "patch" for the live patch
; out:  the view ran until q or Esc; the screen is cleared
; clobbers: caller-saved
cmd_glass:
    push rdi
    lea rsi, [rel gv_word]
    call str_eq
    pop rdi
    je gv_run
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov qword [rel gl_mem_addr], 0
.word_end:
    mov al, [rdi]
    test al, al
    jz .id
    cmp al, ' '
    je .address
    inc rdi
    jmp .word_end
.address:
    mov byte [rdi], 0
    inc rdi
    call parse_addr
    jc .usage
    mov rcx, 0xfffff000             ; the identity map ends at 4 GiB
    cmp rax, rcx
    jae .usage
    mov [rel gl_mem_addr], rax
.id:
    mov rdi, rbx
    call parse_dec
    jc .usage
    cmp rax, MAX_TASKS
    jae .refused
    mov r12d, eax
    mov edi, eax
    call task_entry
    jc .refused
    mov rbx, rax
    cmp byte [rel console_ready], 0
    je .refused
    mov [rel gl_task], r12d
    mov rdi, [rbx + TASK_FRAME]
    call gl_regs_reset
    lea rdi, [rel kernel_console]
    call console_clear
.frame:
    mov rax, [rbx + TASK_STATE]
    cmp rax, TASK_READY
    je .live
    cmp rax, TASK_PAUSED
    jne .ended
.live:
    call gl_render
    mov r13, [rel timer_ticks]
    add r13, GL_REFRESH_MS
.wait:
    call kbd_poll
    jnz .key
    cmp [rel timer_ticks], r13
    jae .frame
    call task_yield
    jmp .wait
.key:
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    cmp eax, 'p'
    je .toggle
    cmp eax, 's'
    je .step
    cmp eax, 'f'
    je .forge
    jmp .frame
.toggle:
    mov edi, r12d
    call task_pause
    jnc .frame
    mov edi, r12d
    call task_resume
    jmp .frame
.step:
    mov edi, r12d
    call task_step
    jmp .frame
.forge:
    mov rax, [rbx + TASK_FRAME]
    mov rdi, [rax + INT_FRAME_RIP]
    call gl_module_of
    jc .frame
    mov rdi, rax
    call cmd_edit
    jmp .done
.ended:
    call shell_clear_screen
    lea rdi, [rel gl_msg_ended]
    call kputs
    jmp .done
.quit:
    call shell_clear_screen
    jmp .done
.usage:
    lea rdi, [rel gl_msg_usage]
    call kputs
    jmp .done
.refused:
    lea rdi, [rel gl_msg_refused]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: gl_render
; in:   gl_task set, its frame saved
; out:  title, the four panes and the key help drawn
; clobbers: caller-saved
gl_render:
    push rbx
    push r12
    push r13
    mov eax, [rel gl_task]
    imul eax, TASK_SIZE
    lea rbx, [rel sched_tasks]
    add rbx, rax
    mov r12, [rbx + TASK_FRAME]
    xor edi, edi
    xor esi, esi
    mov edx, 1000
    mov ecx, GL_TITLE_BG
    call gl_fill
    mov edi, 1
    xor esi, esi
    lea rdx, [rel gl_msg_title]
    mov ecx, GL_ACCENT
    mov r8d, GL_TITLE_BG
    call gl_text
    mov edi, eax
    xor esi, esi
    lea rdx, [rbx + TASK_NAME]
    mov ecx, COLOR_FG
    mov r8d, GL_TITLE_BG
    call gl_text
    lea rdx, [rel gl_msg_running]
    cmp qword [rbx + TASK_STATE], TASK_PAUSED
    jne .state
    lea rdx, [rel gl_msg_paused]
.state:
    lea edi, [rax + 2]
    xor esi, esi
    mov ecx, GL_CHANGED
    mov r8d, GL_TITLE_BG
    call gl_text
    lea r13d, [rax + 2]
    lea rax, [rel gl_line]
    mov [rel dis_out], rax
    mov rdi, [r12 + INT_FRAME_RIP]
    call dis_target
    mov rax, [rel dis_out]
    mov byte [rax], 0
    mov edi, r13d
    xor esi, esi
    lea rdx, [rel gl_line]
    mov ecx, COLOR_FG
    mov r8d, GL_TITLE_BG
    call gl_text
    mov edi, 1
    mov esi, 1
    lea rdx, [rel gl_msg_registers]
    call gl_header
    mov edi, GL_CODE_COL
    mov esi, 1
    lea rdx, [rel gl_msg_code]
    call gl_header
    mov edi, 1
    mov esi, GL_TOP + EXC_REG_COUNT + 1
    lea rdx, [rel gl_msg_stack]
    call gl_header
    mov edi, GL_CODE_COL + 20
    mov esi, GL_TOP + EXC_REG_COUNT + 1
    lea rdx, [rel gl_msg_memory]
    call gl_header
    mov edi, 1
    mov esi, GL_TOP
    mov rdx, r12
    call gl_regs
    mov rdi, [r12 + INT_FRAME_RIP]
    call gl_code
    mov rax, [rel kernel_console + CON_ROWS]    ; rows above the key help
    sub eax, GL_TOP + EXC_REG_COUNT + 3
    mov r13d, eax
    jle .keys
    xor edi, edi                    ; the stack pane's lines vary in length
    mov esi, (GL_TOP + EXC_REG_COUNT + 2) * FONT_HEIGHT
    mov edx, (GL_CODE_COL + 19) * 8
    mov ecx, eax
    shl ecx, 4
    mov r8d, COLOR_BG
    call fb_fill_rect
    mov edi, 1
    mov esi, GL_TOP + EXC_REG_COUNT + 2
    mov rdx, [r12 + INT_FRAME_RSP]
    mov ecx, r13d
    call gl_stack
    mov rdx, [rel gl_mem_addr]
    test rdx, rdx
    jnz .memory
    mov rdx, [r12 + INT_FRAME_RIP]
.memory:
    mov edi, GL_CODE_COL + 20
    mov esi, GL_TOP + EXC_REG_COUNT + 2
    mov ecx, r13d
    call gl_memory
.keys:
    mov rsi, [rel kernel_console + CON_ROWS]
    dec esi
    lea rdx, [rel gl_msg_keys]
    call gl_bar
    pop r13
    pop r12
    pop rbx
    ret

; name: gl_header
; in:   edi = column, esi = row, rdx = text
; out:  the text drawn in the accent colour
; clobbers: caller-saved
gl_header:
    mov ecx, GL_ACCENT
    mov r8d, COLOR_BG
    jmp gl_text

; name: gl_bar
; in:   esi = row, rdx = text
; out:  the row filled with the title colour and the text drawn on it
; clobbers: caller-saved
gl_bar:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, esi
    mov r12, rdx
    xor edi, edi
    mov edx, 1000
    mov ecx, GL_TITLE_BG
    call gl_fill
    mov edi, 1
    mov esi, ebx
    mov rdx, r12
    mov ecx, COLOR_FG
    mov r8d, GL_TITLE_BG
    call gl_text
    add rsp, 8
    pop r12
    pop rbx
    ret

gl_msg_title     db "glass  ", 0
gl_msg_running   db "running", 0
gl_msg_paused    db "paused ", 0
gl_msg_registers db "registers", 0
gl_msg_code      db "code", 0
gl_msg_stack     db "stack", 0
gl_msg_memory    db "memory", 0
gl_msg_keys      db "p pause/resume   s step   f open in forge   q quit", 0
gl_msg_usage     db "usage: glass <task id> [0xaddress|label]", 10, 0
gl_msg_refused   db "[glass] no such task, or no screen", 10, 0
gl_msg_ended     db "[glass] the task ended", 10, 0

section .bss
alignb 8
gl_mem_addr resq 1
gl_task     resd 1
section .text
