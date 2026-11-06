; Forge lexer: cursor over the current line, names, numbers, and the
; shared assembler state. Errors unwind through forge_fail.

FORGE_NAME_MAX   equ 47
FORGE_LABEL_SIZE equ 64             ; name (48 bytes), value, pass that set it
FORGE_LABEL_VAL  equ 48
FORGE_LABEL_PASS equ 56
FORGE_LABELS_MAX equ 256
FORGE_JUMPS_MAX  equ 1024
FORGE_PASSES_MAX equ 16

; name: forge_fail
; in:   rdi = error message
; out:  returns from forge_assemble with CF=1
; clobbers: everything
forge_fail:
    mov [rel forge_error], rdi
    mov rax, [rel forge_line_no]
    mov [rel forge_error_line], rax
    mov rsp, [rel forge_saved_rsp]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    stc
    ret

; name: forge_skip
; in:   forge_cur
; out:  forge_cur past spaces and tabs; at the line end if a comment starts
; clobbers: rax
forge_skip:
    mov rax, [rel forge_cur]
.next:
    cmp rax, [rel forge_line_end]
    jae .done
    cmp byte [rax], ' '
    je .space
    cmp byte [rax], 9
    je .space
    cmp byte [rax], 13
    je .space
    cmp byte [rax], ';'
    jne .done
    mov rax, [rel forge_line_end]
    jmp .done
.space:
    inc rax
    jmp .next
.done:
    mov [rel forge_cur], rax
    ret

; name: forge_at_end
; in:   forge_cur
; out:  ZF=1 if the cursor is at the end of the line
; clobbers: rax
forge_at_end:
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .yes
    cmp byte [rax], ';'
    ret
.yes:
    cmp eax, eax
    ret

; name: forge_expect
; in:   dil = character
; out:  forge_cur past it (and spaces before it), fails if it is not there
; clobbers: rax
forge_expect:
    call forge_skip
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .missing
    cmp [rax], dil
    jne .missing
    inc qword [rel forge_cur]
    ret
.missing:
    lea rdi, [rel forge_msg_syntax]
    jmp forge_fail

; name: forge_ident
; in:   rdi = 48-byte buffer, forge_cur at a name
; out:  rax = name length (0 if no name here), name copied zero-terminated,
;       forge_cur past it
; clobbers: rcx, rdx, rsi
forge_ident:
    mov rsi, [rel forge_cur]
    xor eax, eax
    movzx edx, byte [rsi]
    cmp edx, '0'                    ; a name does not start with a digit
    jb .char
    cmp edx, '9'
    jbe .done
.char:
    cmp rsi, [rel forge_line_end]
    jae .done
    movzx edx, byte [rsi]
    mov ecx, edx
    or ecx, 0x20
    sub ecx, 'a'
    cmp ecx, 26
    jb .take
    cmp edx, '_'
    je .take
    cmp edx, '.'
    je .take
    mov ecx, edx
    sub ecx, '0'
    cmp ecx, 10
    jae .done
.take:
    cmp eax, FORGE_NAME_MAX
    jae .long
    mov [rdi + rax], dl
    inc eax
    inc rsi
    jmp .char
.done:
    mov byte [rdi + rax], 0
    mov [rel forge_cur], rsi
    ret
.long:
    lea rdi, [rel forge_msg_long]
    jmp forge_fail

; name: forge_copy_name
; in:   rdi = destination, rsi = zero-terminated name
; out:  name copied
; clobbers: rax, rdi, rsi
forge_copy_name:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz forge_copy_name
    ret

; name: forge_number
; in:   forge_cur at a decimal or 0x hex number
; out:  rax = value, forge_cur past it
; clobbers: rcx, rdx, rsi
forge_number:
    mov rsi, [rel forge_cur]
    xor eax, eax
    cmp byte [rsi], '0'
    jne .decimal
    movzx ecx, byte [rsi + 1]
    or ecx, 0x20
    cmp ecx, 'x'
    jne .decimal
    add rsi, 2
.hex:
    cmp rsi, [rel forge_line_end]
    jae .done
    movzx ecx, byte [rsi]
    mov edx, ecx
    sub edx, '0'
    cmp edx, 10
    jb .hex_digit
    or ecx, 0x20
    lea edx, [rcx - 'a' + 10]
    sub ecx, 'a'
    cmp ecx, 6
    jae .done
.hex_digit:
    shl rax, 4
    add rax, rdx
    inc rsi
    jmp .hex
.decimal:
    cmp rsi, [rel forge_line_end]
    jae .done
    movzx ecx, byte [rsi]
    sub ecx, '0'
    cmp ecx, 10
    jae .done
    imul rax, rax, 10
    add rax, rcx
    inc rsi
    jmp .decimal
.done:
    mov [rel forge_cur], rsi
    ret

forge_msg_converge  db "jump sizes do not settle", 0
forge_msg_undefined db "undefined name", 0
forge_msg_syntax    db "syntax error", 0
forge_msg_trailing  db "unexpected text after the statement", 0
forge_msg_string    db "bad string", 0
forge_msg_full      db "output buffer full", 0
forge_msg_long      db "name too long", 0
forge_msg_labels    db "too many labels", 0
forge_msg_twice     db "label defined twice", 0
forge_msg_expr      db "bad expression", 0

section .bss
alignb 8
forge_saved_rsp   resq 1
forge_src         resq 1
forge_src_end     resq 1
forge_origin      resq 1
forge_out         resq 1
forge_out_size    resq 1
forge_pc          resq 1
forge_pass        resq 1
forge_changed     resq 1
forge_unknown     resq 1
forge_cur         resq 1
forge_line_start  resq 1
forge_line_end    resq 1
forge_line_no     resq 1
forge_jump_index  resq 1
forge_data_size   resq 1
forge_label_count resq 1
forge_error       resq 1
forge_error_line  resq 1
forge_word        resb FORGE_NAME_MAX + 1
forge_sym_word    resb FORGE_NAME_MAX + 1
forge_label_name  resb FORGE_NAME_MAX + 1
forge_name_buf    resb FORGE_NAME_MAX + 1
forge_parent      resb FORGE_NAME_MAX + 1
forge_jump_long   resb FORGE_JUMPS_MAX
alignb 8
forge_labels      resb FORGE_LABEL_SIZE * FORGE_LABELS_MAX
section .text
