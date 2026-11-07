; File manager: `files` takes the screen and lists every file with its size.
; Up and Down select, Enter opens the file in the editor, r runs a .asm
; program, n creates a file, Del or d deletes a user file, q or Esc leave.
; It draws through the monitor's console and helpers (apps/monitor.asm).

FM_FIRST    equ 3                   ; screen row of the first file
FM_SIZE_COL equ 36
FM_SEL_BG   equ 0x003b4252

; name: cmd_files
; in:   rdi = arguments (ignored)
; out:  the file manager ran until q or Esc; the screen is cleared
; clobbers: caller-saved
cmd_files:
    push rbx
    cmp byte [rel console_ready], 0
    je .no_screen
    mov dword [rel fm_sel], 0
    mov dword [rel fm_top], 0
    mov qword [rel fm_status], 0
.init:
    lea rdi, [rel mon_con]
    xor esi, esi
    xor edx, edx
    mov rcx, [rel kernel_console + CON_COLS]
    mov r8, [rel kernel_console + CON_ROWS]
    call console_init
.redraw:
    call fm_draw
    mov qword [rel fm_status], 0
.wait:
    call fm_key
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    cmp eax, KEY_UP
    je .up
    cmp eax, KEY_DOWN
    je .down
    cmp eax, 10
    je .edit
    cmp eax, 'r'
    je .run
    cmp eax, 'n'
    je .new
    cmp eax, 'd'
    je .delete
    cmp eax, KEY_DEL
    je .delete
    jmp .wait
.up:
    cmp dword [rel fm_sel], 0
    je .wait
    dec dword [rel fm_sel]
    jmp .redraw
.down:
    call fm_count
    mov ecx, [rel fm_sel]
    inc ecx
    cmp ecx, eax
    jae .wait
    mov [rel fm_sel], ecx
    jmp .redraw
.edit:
    call fm_pick
    jc .wait
    lea rdi, [rel fm_name]
    call cmd_edit
    jmp .init
.run:
    call fm_pick
    jc .wait
    lea rdi, [rel fm_name]
    call str_skip                   ; rax = past the terminator
    lea rdi, [rel fm_name + 5]
    cmp rax, rdi
    jb .not_program
    cmp dword [rax - 5], ".asm"
    jne .not_program
    call shell_clear_screen
    lea rdi, [rel fm_name]
    call cmd_run
    lea rdi, [rel fm_msg_back]
    call kputs
    call fm_key
    jmp .init
.not_program:
    lea rax, [rel fm_msg_not_asm]
    mov [rel fm_status], rax
    jmp .redraw
.new:
    call shell_clear_screen
    lea rdi, [rel fm_msg_new]
    call kputs
    lea rdi, [rel fm_name]
    call shell_readline
    test rax, rax
    jz .init
    lea rdi, [rel fm_name]
    call cmd_edit
    jmp .init
.delete:
    call fm_pick
    jc .wait
    test dword [rax + SRC_DIR_FLAGS], SRC_FILE
    jz .module
    lea rax, [rel fm_msg_confirm]
    mov [rel fm_status], rax
    call fm_draw
    mov qword [rel fm_status], 0
    call fm_key
    cmp eax, 'y'
    jne .redraw
    lea rdi, [rel fm_name]
    call src_remove
    lea rax, [rel fm_msg_removed]
    mov [rel fm_status], rax
    call fm_count
    cmp [rel fm_sel], eax
    jb .redraw
    test eax, eax
    jz .redraw
    dec eax
    mov [rel fm_sel], eax
    jmp .redraw
.module:
    lea rax, [rel fm_msg_module]
    mov [rel fm_status], rax
    jmp .redraw
.quit:
    call shell_clear_screen
    pop rbx
    ret
.no_screen:
    lea rdi, [rel br_msg_no_screen]
    call kputs
    pop rbx
    ret

; name: fm_key
; in:   none
; out:  eax = the next key, waited for
; clobbers: caller-saved
fm_key:
    sub rsp, 8
.poll:
    call kbd_poll
    jnz .got
    call task_yield
    jmp .poll
.got:
    add rsp, 8
    ret

; name: fm_count
; in:   none
; out:  eax = number of files
; clobbers: rax
fm_count:
    mov rax, [rel src_area]
    test rax, rax
    jz .ret
    mov eax, [rax + SRC_HDR_COUNT]
.ret:
    ret

; name: fm_entry
; in:   edi = file index, below fm_count
; out:  rax = its directory entry
; clobbers: rax, rdi
fm_entry:
    imul edi, edi, SRC_DIR_ENTRY
    mov rax, [rel src_area]
    lea rax, [rax + rdi + SRC_DIR]
    ret

; name: fm_pick
; in:   none
; out:  rax = the selected entry, its path copied to fm_name; CF=1 if
;       there are no files
; clobbers: rax, rcx, rdi, rsi
fm_pick:
    call fm_count
    cmp [rel fm_sel], eax
    jae .none
    mov edi, [rel fm_sel]
    call fm_entry
    mov rsi, rax
    lea rdi, [rel fm_name]
    mov ecx, SRC_NAME_MAX + 1
    rep movsb
    clc
    ret
.none:
    stc
    ret

; name: fm_draw
; in:   none
; out:  the title, the files from fm_top with fm_sel highlighted, and
;       fm_status on the last row
; clobbers: caller-saved
fm_draw:
    push rbx
    push r12
    push r13
    mov qword [rel mon_con + CON_CX], 0
    mov qword [rel mon_con + CON_CY], 0
    mov edi, MON_TITLE
    lea rsi, [rel fm_msg_title]
    call mon_text
    call mon_eol
    call mon_eol
    mov edi, MON_TITLE
    lea rsi, [rel fm_msg_header]
    call mon_text
    call mon_eol
    mov r13, [rel mon_con + CON_ROWS]
    sub r13d, FM_FIRST + 2          ; rows for files, above a gap and the status
    mov eax, [rel fm_sel]
    cmp eax, [rel fm_top]
    jae .below_top
    mov [rel fm_top], eax
.below_top:
    mov ecx, [rel fm_top]
    add ecx, r13d
    cmp eax, ecx
    jb .shown
    sub eax, r13d
    inc eax
    mov [rel fm_top], eax
.shown:
    mov r12d, [rel fm_top]
.row:
    test r13d, r13d
    jz .status
    call fm_count
    cmp r12d, eax
    jae .blank
    mov edi, r12d
    call fm_entry
    mov rbx, rax
    cmp r12d, [rel fm_sel]
    jne .colours
    mov qword [rel mon_con + CON_BG], FM_SEL_BG
.colours:
    test dword [rbx + SRC_DIR_FLAGS], SRC_FILE
    jnz .name
    mov qword [rel mon_con + CON_FG], MON_FREE + 0x00303030
.name:
    mov edi, ' '
    call mon_putc
    mov rsi, rbx
    call mon_plain
    mov edi, FM_SIZE_COL
    call mon_pad
    mov edi, [rbx + SRC_DIR_LEN]
    call mon_dec
    lea rsi, [rel files_msg_bytes]
    call mon_plain
    test dword [rbx + SRC_DIR_FLAGS], SRC_FILE
    jnz .eol
    lea rsi, [rel files_msg_module]
    call mon_plain
.eol:
    call mon_eol
    mov qword [rel mon_con + CON_FG], COLOR_FG
    mov qword [rel mon_con + CON_BG], COLOR_BG
    jmp .next
.blank:
    call mon_eol
.next:
    inc r12d
    dec r13d
    jmp .row
.status:
    call mon_eol
    mov rsi, [rel fm_status]
    test rsi, rsi
    jz .pad
    mov edi, MON_USED
    call mon_text
.pad:
    mov rdi, [rel mon_con + CON_COLS]
    dec edi                         ; the last cell would wrap and scroll
    call mon_pad
    pop r13
    pop r12
    pop rbx
    ret

fm_msg_title    db " Vitre files: Enter edits, r runs, n new, Del deletes, q quits", 0
fm_msg_header   db " name                               size", 0
fm_msg_back     db 10, "[files] press a key to go back", 10, 0
fm_msg_new      db "new file name, empty cancels: ", 0
fm_msg_not_asm  db " only .asm files run", 0
fm_msg_confirm  db " delete this file? y deletes, any other key keeps it", 0
fm_msg_removed  db " removed", 0
fm_msg_module   db " kernel modules cannot be deleted", 0

section .bss
alignb 8
fm_status resq 1                    ; message for the last row, 0 for none
fm_sel    resd 1
fm_top    resd 1
fm_name   resb SHELL_LINE_MAX
section .text
