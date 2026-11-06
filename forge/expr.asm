; Forge labels and expressions. A name resolves to the module's own label
; first, then to the kernel's label table.

; name: forge_full_name
; in:   rdi = name; a local name (".x") is joined to the current parent label
; out:  rax = forge_name_buf holding the full name
; clobbers: rcx, rdx, rdi, rsi
forge_full_name:
    push rdi
    lea rdi, [rel forge_name_buf]
    pop rsi
    cmp byte [rsi], '.'
    jne .copy
    push rsi
    lea rsi, [rel forge_parent]
    call forge_copy_name
    dec rdi
    pop rsi
.copy:
    mov rdx, rdi
    lea rcx, [rel forge_name_buf]
    sub rdx, rcx
    mov rdi, rsi
    call str_skip
    sub rax, rsi
    add rax, rdx
    cmp rax, FORGE_NAME_MAX + 1
    ja .long
    lea rdi, [rel forge_name_buf]
    add rdi, rdx
    call forge_copy_name
    lea rax, [rel forge_name_buf]
    ret
.long:
    lea rdi, [rel forge_msg_long]
    jmp forge_fail

; name: forge_define
; in:   rdi = label name (local or not), rsi = value
; out:  label set for this pass; forge_changed set if its value moved
; clobbers: caller-saved
forge_define:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rsi
    cmp byte [rdi], '.'
    je .local
    push rdi
    sub rsp, 8
    mov rsi, rdi
    lea rdi, [rel forge_parent]
    call forge_copy_name
    add rsp, 8
    pop rdi
.local:
    call forge_full_name
    mov rdi, rax
    call forge_find
    jnc .found
    mov rbx, [rel forge_label_count]
    cmp rbx, FORGE_LABELS_MAX
    jae .full
    inc qword [rel forge_label_count]
    imul rbx, FORGE_LABEL_SIZE
    lea rax, [rel forge_labels]
    add rbx, rax
    mov rdi, rbx
    lea rsi, [rel forge_name_buf]
    call forge_copy_name
    mov qword [rbx + FORGE_LABEL_PASS], 0
    mov [rbx + FORGE_LABEL_VAL], r12
    inc qword [rel forge_changed]
    jmp .set
.found:
    mov rbx, rax
    mov rax, [rel forge_pass]
    cmp [rbx + FORGE_LABEL_PASS], rax
    je .twice
    cmp [rbx + FORGE_LABEL_VAL], r12
    je .set
    mov [rbx + FORGE_LABEL_VAL], r12
    inc qword [rel forge_changed]
.set:
    mov rax, [rel forge_pass]
    mov [rbx + FORGE_LABEL_PASS], rax
    add rsp, 8
    pop r12
    pop rbx
    ret
.full:
    lea rdi, [rel forge_msg_labels]
    jmp forge_fail
.twice:
    lea rdi, [rel forge_msg_twice]
    jmp forge_fail

; name: forge_find
; in:   rdi = full label name
; out:  rax = label record, CF=1 if the module has no such label
; clobbers: rcx, rdx, rsi
forge_find:
    push rbx
    push r12
    push r13
    mov r12, rdi
    lea rbx, [rel forge_labels]
    mov r13, [rel forge_label_count]
.next:
    test r13, r13
    jz .missing
    mov rdi, r12
    mov rsi, rbx
    call str_eq
    je .found
    add rbx, FORGE_LABEL_SIZE
    dec r13
    jmp .next
.found:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    clc
    ret
.missing:
    pop r13
    pop r12
    pop rbx
    stc
    ret

; name: lab_lookup
; in:   rdi = name
; out:  rax = value of the kernel label or equ, CF=1 if there is none
; clobbers: rcx, rdx, rsi
lab_lookup:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    lea rbx, [rel lab_table]
.next:
    cmp byte [rbx + 8], 0
    je .missing
    mov rdi, r12
    lea rsi, [rbx + 8]
    call str_eq
    je .found
    lea rdi, [rbx + 8]
    call str_skip
    mov rbx, rax
    jmp .next
.found:
    mov rax, [rbx]
    add rsp, 8
    pop r12
    pop rbx
    clc
    ret
.missing:
    add rsp, 8
    pop r12
    pop rbx
    stc
    ret

; name: forge_symbol
; in:   rdi = name as written
; out:  rax = its value: the module's label first, then the kernel's.
;       Unknown names are 0 and set forge_unknown, which fails the assembly
;       if it is still set after the last pass.
; clobbers: rcx, rdx, rdi, rsi
forge_symbol:
    push rbx
    mov rbx, rdi
    call forge_full_name
    mov rdi, rax
    call forge_find
    jc .kernel
    mov rax, [rax + FORGE_LABEL_VAL]
    pop rbx
    ret
.kernel:
    cmp byte [rbx], '.'
    je .unknown
    mov rdi, rbx
    call lab_lookup
    jc .unknown
    pop rbx
    ret
.unknown:
    inc qword [rel forge_unknown]
    xor eax, eax
    pop rbx
    ret

; name: forge_expr
; in:   forge_cur at an expression: terms joined with + and -
; out:  rax = value
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_expr:
    push rbx
    call forge_term
    mov rbx, rax
.op:
    call forge_skip
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .done
    cmp byte [rax], '+'
    je .add
    cmp byte [rax], '-'
    jne .done
    inc qword [rel forge_cur]
    call forge_term
    sub rbx, rax
    jmp .op
.add:
    inc qword [rel forge_cur]
    call forge_term
    add rbx, rax
    jmp .op
.done:
    mov rax, rbx
    pop rbx
    ret

; name: forge_term
; in:   forge_cur at factors joined with *
; out:  rax = value
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_term:
    push rbx
    call forge_factor
    mov rbx, rax
.op:
    call forge_skip
    mov rax, [rel forge_cur]
    cmp rax, [rel forge_line_end]
    jae .done
    cmp byte [rax], '*'
    jne .done
    inc qword [rel forge_cur]
    call forge_factor
    imul rbx, rax
    jmp .op
.done:
    mov rax, rbx
    pop rbx
    ret

; name: forge_factor
; in:   forge_cur at a number, 'c', name, -factor or (expr)
; out:  rax = value
; clobbers: everything but rbx, rbp, r12-r15, rsp
forge_factor:
    sub rsp, 8
    call forge_skip
    mov rsi, [rel forge_cur]
    cmp rsi, [rel forge_line_end]
    jae .bad
    movzx eax, byte [rsi]
    cmp eax, '-'
    je .negate
    cmp eax, '('
    je .paren
    cmp eax, 0x27                   ; quote
    je .char
    sub eax, '0'
    cmp eax, 10
    jb .number
    lea rdi, [rel forge_sym_word]
    call forge_ident
    test rax, rax
    jz .bad
    lea rdi, [rel forge_sym_word]
    call forge_symbol
    add rsp, 8
    ret
.negate:
    inc qword [rel forge_cur]
    call forge_factor
    neg rax
    add rsp, 8
    ret
.paren:
    inc qword [rel forge_cur]
    call forge_expr
    push rax
    mov edi, ')'
    call forge_expect
    pop rax
    add rsp, 8
    ret
.char:
    lea rax, [rsi + 2]
    cmp rax, [rel forge_line_end]
    jae .bad
    movzx eax, byte [rsi + 1]
    cmp byte [rsi + 2], 0x27
    jne .bad
    add rsi, 3
    mov [rel forge_cur], rsi
    add rsp, 8
    ret
.number:
    call forge_number
    add rsp, 8
    ret
.bad:
    lea rdi, [rel forge_msg_expr]
    jmp forge_fail
