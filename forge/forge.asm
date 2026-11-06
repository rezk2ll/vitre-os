; Forge assembler driver: passes, lines, directives and data.
;
; Assembles Vitre dialect source (docs/DIALECT.md) into a buffer, for a given
; load address. One assembly runs at a time: the state lives in .bss. Passes
; repeat until no label moves and no jump changes size. Errors unwind to
; forge_assemble through forge_fail.

; name: forge_assemble
; in:   rdi = source, rsi = source length, rdx = load address,
;       rcx = output buffer, r8 = output buffer size
; out:  rax = bytes produced; CF=1 on error, with forge_error (message) and
;       forge_error_line set
; clobbers: caller-saved
forge_assemble:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [rel forge_saved_rsp], rsp
    mov [rel forge_src], rdi
    add rsi, rdi
    mov [rel forge_src_end], rsi
    mov [rel forge_origin], rdx
    mov [rel forge_out], rcx
    mov [rel forge_out_size], r8
    mov qword [rel forge_label_count], 0
    lea rdi, [rel forge_jump_long]
    xor eax, eax
    mov ecx, FORGE_JUMPS_MAX
    rep stosb
    mov qword [rel forge_pass], 0
.pass:
    inc qword [rel forge_pass]
    cmp qword [rel forge_pass], FORGE_PASSES_MAX
    ja .no_converge
    mov qword [rel forge_changed], 0
    mov qword [rel forge_unknown], 0
    call forge_run_pass
    cmp qword [rel forge_pass], 1
    je .pass                        ; the first pass only learns the labels
    cmp qword [rel forge_changed], 0
    jne .pass
    cmp qword [rel forge_unknown], 0
    jne .undefined
    mov rax, [rel forge_pc]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    clc
    ret
.no_converge:
    lea rdi, [rel forge_msg_converge]
    jmp forge_fail
.undefined:
    lea rdi, [rel forge_msg_undefined]
    jmp forge_fail

; name: forge_run_pass
; in:   forge state reset for a pass
; out:  every line assembled once, forge_pc = bytes produced
; clobbers: everything but rsp
forge_run_pass:
    sub rsp, 8
    mov qword [rel forge_pc], 0
    mov qword [rel forge_line_no], 0
    mov qword [rel forge_jump_index], 0
    mov byte [rel forge_parent], 0
    mov rax, [rel forge_src]
    mov [rel forge_cur], rax
.line:
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_src_end]
    jae .done
    inc qword [rel forge_line_no]
    mov [rel forge_line_start], rax
    mov rdi, rax                    ; the line ends at '\n', ';' or the end
.find_end:
    cmp rdi, [rel forge_src_end]
    jae .ended
    cmp byte [rdi], 10
    je .ended
    inc rdi
    jmp .find_end
.ended:
    mov [rel forge_line_end], rdi
    call forge_line
    mov rax, [rel forge_line_end]
    inc rax
    mov [rel forge_cur], rax
    jmp .line
.done:
    add rsp, 8
    ret

; name: forge_line
; in:   forge_cur at the start of a line, forge_line_end set
; out:  the label, directive or instruction on the line assembled
; clobbers: everything but rsp
forge_line:
    sub rsp, 8
    call forge_skip
    call forge_at_end
    je .done
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_start] ; a label starts in column 0
    jne .statement
    lea rdi, [rel forge_word]
    call forge_ident
    test rax, rax
    jz .bad
    mov rax, [rel forge_cur]
    cmp byte [rax], ':'
    jne .data_label
    inc qword [rel forge_cur]
    lea rdi, [rel forge_word]
    mov rsi, [rel forge_pc]
    add rsi, [rel forge_origin]
    call forge_define
    jmp .statement
.data_label:
    lea rdi, [rel forge_label_name] ; "name db ...": defined by the directive
    lea rsi, [rel forge_word]
    call forge_copy_name
    call forge_skip
    lea rdi, [rel forge_word]
    call forge_ident
    test rax, rax
    jz .bad
    lea rdi, [rel forge_word]
    lea rsi, [rel forge_dir_equ]
    call str_eq
    je .equ
    lea rdi, [rel forge_label_name]
    mov rsi, [rel forge_pc]
    add rsi, [rel forge_origin]
    call forge_define
    jmp .mnemonic
.equ:
    call forge_expr
    lea rdi, [rel forge_label_name]
    mov rsi, rax
    call forge_define
    jmp .done
.statement:
    call forge_skip
    call forge_at_end
    je .done
    lea rdi, [rel forge_word]
    call forge_ident
    test rax, rax
    jz .bad
.mnemonic:
    call forge_statement
.done:
    call forge_skip
    call forge_at_end
    jne .trailing
    add rsp, 8
    ret
.bad:
    lea rdi, [rel forge_msg_syntax]
    jmp forge_fail
.trailing:
    lea rdi, [rel forge_msg_trailing]
    jmp forge_fail

; name: forge_statement
; in:   forge_word = directive or mnemonic, forge_cur after it
; out:  the statement assembled, with "times" repeating it
; clobbers: everything but rsp
forge_statement:
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [rel forge_word]
    lea rsi, [rel forge_dir_times]
    call str_eq
    jne .once
    call forge_expr
    mov rbx, rax
    call forge_skip
    lea rdi, [rel forge_word]
    call forge_ident
    test rax, rax
    jz .bad
    mov r12, [rel forge_cur]
    mov rax, [rel forge_line_end]   ; times 0: nothing to emit or check
    mov [rel forge_cur], rax
.repeat:
    test rbx, rbx
    jz .done
    mov [rel forge_cur], r12
    call forge_data_or_instruction
    dec rbx
    jmp .repeat
.once:
    call forge_data_or_instruction
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
.bad:
    lea rdi, [rel forge_msg_syntax]
    jmp forge_fail

; name: forge_data_or_instruction
; in:   forge_word = db, dw, dd, dq or a mnemonic
; out:  data or one instruction emitted
; clobbers: everything but rsp
forge_data_or_instruction:
    sub rsp, 8
    lea rsi, [rel forge_data_dirs]
.dir:
    movzx eax, byte [rsi]           ; record: item size, then name
    test eax, eax
    jz .instruction
    mov [rel forge_data_size], rax
    inc rsi
    push rsi
    sub rsp, 8
    lea rdi, [rel forge_word]
    call str_eq
    lea rsp, [rsp + 8]
    pop rdi
    je .data
    call str_skip
    mov rsi, rax
    jmp .dir
.data:
    call forge_data
    add rsp, 8
    ret
.instruction:
    call forge_instruction
    add rsp, 8
    ret

; name: forge_data
; in:   forge_data_size = 1, 2, 4 or 8, forge_cur at the items
; out:  comma-separated numbers (and strings for db) emitted
; clobbers: everything but rsp
forge_data:
    push rbx
.item:
    call forge_skip
    mov rbx, [rel forge_cur]
    cmp byte [rbx], '"'
    jne .number
    cmp qword [rel forge_data_size], 1
    jne .bad
.char:
    inc rbx
    cmp rbx, [rel forge_line_end]
    jae .bad
    movzx edi, byte [rbx]
    cmp edi, '"'
    je .string_end
    call forge_emit_byte
    jmp .char
.string_end:
    inc rbx
    mov [rel forge_cur], rbx
    jmp .next
.number:
    call forge_expr
    mov rdi, rax
    mov rsi, [rel forge_data_size]
    call forge_emit_value
.next:
    call forge_skip
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .done
    cmp byte [rax], ','
    jne .done
    inc qword [rel forge_cur]
    jmp .item
.done:
    pop rbx
    ret
.bad:
    lea rdi, [rel forge_msg_string]
    jmp forge_fail

; name: forge_emit_byte
; in:   dil = byte
; out:  byte stored at forge_pc, which advances
; clobbers: rax
forge_emit_byte:
    mov rax, [rel forge_pc]
    cmp rax, [rel forge_out_size]
    jae .full
    add rax, [rel forge_out]
    mov [rax], dil
    inc qword [rel forge_pc]
    ret
.full:
    lea rdi, [rel forge_msg_full]
    jmp forge_fail

; name: forge_emit_value
; in:   rdi = value, rsi = byte count, little-endian
; out:  bytes emitted
; clobbers: rax, rcx, rdi, rsi
forge_emit_value:
    mov rcx, rdi
.byte:
    mov edi, ecx
    call forge_emit_byte
    shr rcx, 8
    dec rsi
    jnz .byte
    ret

forge_dir_equ   db "equ", 0
forge_dir_times db "times", 0
forge_data_dirs db 1, "db", 0, 2, "dw", 0, 4, "dd", 0, 8, "dq", 0, 0
