; Files: ls, cat and rm over the source area, where user files sit next to
; the kernel modules.

FILES_SIZE_COLUMN equ 34

; name: cmd_ls
; in:   rdi = arguments (ignored)
; out:  one line per file: its path and size, and whether it is a module
; clobbers: caller-saved
cmd_ls:
    push rbx
    push r12
    push r13
    mov rbx, [rel src_area]
    test rbx, rbx
    jz .done
    mov r12d, [rbx + SRC_HDR_COUNT]
    lea rbx, [rbx + SRC_DIR]
.entry:
    test r12d, r12d
    jz .done
    lea rdi, [rel shell_indent]
    call kputs
    mov rdi, rbx
    call kputs
    mov rdi, rbx
    call str_skip
    sub rax, rbx
    mov r13d, FILES_SIZE_COLUMN
    sub r13d, eax
.pad:
    mov edi, ' '
    call kputc
    dec r13d
    jg .pad
    mov edi, [rbx + SRC_DIR_LEN]
    call [rel jt_kput_dec]
    lea rdi, [rel files_msg_bytes]
    call kputs
    test dword [rbx + SRC_DIR_FLAGS], SRC_FILE
    jnz .line_end
    lea rdi, [rel files_msg_module]
    call kputs
.line_end:
    mov edi, 10
    call kputc
    add rbx, SRC_DIR_ENTRY
    dec r12d
    jmp .entry
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_cat
; in:   rdi = path
; out:  the file's text on the console, ending with a new line
; clobbers: caller-saved
cmd_cat:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call src_find
    jc .missing
    mov rbx, rax
    mov r12, rdx
    mov r13d, 10                    ; an empty file prints nothing
.char:
    test r12, r12
    jz .end
    movzx edi, byte [rbx]
    mov r13d, edi
    call kputc
    inc rbx
    dec r12
    jmp .char
.end:
    cmp r13d, 10
    je .done
    mov edi, 10
    call kputc
    jmp .done
.missing:
    lea rdi, [rel files_msg_missing]
    call kputs
    mov rdi, rbx
    call kputs
    mov edi, 10
    call kputc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_rm
; in:   rdi = path of a user file
; out:  the file removed from the source area, or why not on the log
; clobbers: caller-saved
cmd_rm:
    push rbx
    mov rbx, rdi
    call src_remove
    lea rdi, [rel files_msg_removed]
    jnc .print
    lea rdi, [rel files_msg_not_file]
.print:
    call kputs
    mov rdi, rbx
    call kputs
    mov edi, 10
    call kputc
    pop rbx
    ret

files_msg_bytes    db " bytes", 0
files_msg_module   db ", kernel module", 0
files_msg_missing  db "no such file: ", 0
files_msg_removed  db "removed ", 0
files_msg_not_file db "not a user file: ", 0
