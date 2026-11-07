; Reading the kernel source for tools/gen.asm: the %include walk, labels,
; equs and function headers.

; walk(rdi = path): reads the file and runs every line through
; process_line, an %include line through walk instead, each file once
walk:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi
    xor ebx, ebx
.seen:
    cmp rbx, [files_n]
    jae .new
    lea rax, [file_path]
    mov rdi, [rax + rbx * 8]
    mov rsi, r14
    call streq
    je .done
    inc rbx
    jmp .seen
.new:
    mov rdi, r14
    call load_file
    mov r15, [files_n]
    lea rcx, [file_path]
    mov [rcx + r15 * 8], r14
    lea rcx, [file_text]
    mov [rcx + r15 * 8], rax
    lea rcx, [file_len]
    mov [rcx + r15 * 8], rdx
    inc qword [files_n]
    mov r12, rax                    ; line start
    lea r13, [rax + rdx]            ; text end
    xor ebp, ebp                    ; byte offset of the line
    xor ebx, ebx                    ; line number
.line:
    cmp r12, r13
    jae .done
    inc rbx
    mov rdi, r12
    mov rsi, r13
    call line_end
    push rax
    push rax
    mov rdi, r12
    mov rsi, rax
    call match_include
    test rax, rax
    jz .plain
    mov rdi, rax
    call walk
    jmp .advance
.plain:
    mov [cur_file], r15
    mov [cur_no], rbx
    mov [cur_off], rbp
    mov rdi, r12
    mov rsi, [rsp]
    call process_line
.advance:
    pop rax
    pop rax
    mov rcx, rax
    sub rcx, r12
    add rbp, rcx
    mov r12, rax
    jmp .line
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; line_end(rdi = start, rsi = text end): rax = start of the next line
line_end:
    mov rax, rdi
.scan:
    cmp rax, rsi
    jae .ret
    inc rax
    cmp byte [rax - 1], 10
    jne .scan
.ret:
    ret

; match_include(rdi = line, rsi = line end): rax = the path of
; `%include "path"` as a fresh string, 0 for any other line and for
; generated files under build/
match_include:
    push rbx
    mov rbx, rdi
    call skip_space
    mov rdi, rax
    lea rdx, [kw_include]
    mov ecx, 8
    call has_prefix
    jne .no
    lea rdi, [rdi + 8]
    mov rbx, rdi
    call skip_space
    cmp rax, rbx
    je .no
    cmp rax, rsi
    jae .no
    cmp byte [rax], '"'
    jne .no
    lea rbx, [rax + 1]
    mov rdi, rbx
.quote:
    cmp rdi, rsi
    jae .no
    cmp byte [rdi], '"'
    je .closed
    inc rdi
    jmp .quote
.closed:
    cmp rdi, rbx
    je .no
    mov rcx, rdi
    sub rcx, rbx
    cmp rcx, 6
    jb .copy
    cmp dword [rbx], "buil"
    jne .copy
    cmp word [rbx + 4], "d/"
    je .no
.copy:
    mov rsi, rbx
    mov rdi, [arena_ptr]
    mov rax, rdi
    rep movsb
    mov byte [rdi], 0
    inc rdi
    mov [arena_ptr], rdi
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; process_line(rdi = line, rsi = line end), at cur_file, cur_no and
; cur_off: collects a label or equ, a function header and its label
process_line:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    call word_len
    test rax, rax
    jz .header
    mov r13, rax
    lea rdi, [rbx + rax]
    cmp rdi, r12
    jae .header
    cmp byte [rdi], ':'
    je .label
    mov rsi, r12
    call skip_space
    cmp rax, rdi
    je .header
    mov rdi, rax
    call is_keyword
    jne .header
.label:
    mov rax, [labels_n]
    cmp rax, MAX_LABELS
    jae fail_full
    lea rcx, [label_ptr]
    mov [rcx + rax * 8], rbx
    lea rcx, [label_len]
    mov [rcx + rax * 8], r13
    inc qword [labels_n]
.header:
    cmp byte [rbx], ';'
    jne .pending
    lea rdi, [rbx + 1]
    mov rsi, r12
    call skip_space
    mov rdi, rax
    lea rdx, [kw_name]
    mov ecx, 5
    call has_prefix
    jne .patchable
    lea rdi, [rdi + 5]
    call skip_space
    mov rdi, rax
    mov r13, rax
    call word_len
    test rax, rax
    jz .patchable
    mov [pend_name], r13
    mov [pend_len], rax
    mov rax, [cur_file]
    mov [pend_file], rax
    mov rax, [cur_off]
    mov [pend_off], rax
    mov byte [pend_patch], 0
    mov byte [pend_on], 1
    jmp .done
.patchable:
    cmp byte [pend_on], 0
    je .done
    lea rdi, [rbx + 1]
    mov rsi, r12
    call skip_space
    mov rdi, rax
    lea rdx, [kw_patchable]
    mov ecx, 10
    call has_prefix
    jne .done
    lea rdi, [rdi + 10]
    call skip_space
    mov rdi, rax
    lea rdx, [kw_yes]
    mov ecx, 3
    call has_prefix
    jne .done
    mov byte [pend_patch], 1
    jmp .done
.pending:
    cmp byte [pend_on], 0
    je .done
    mov rcx, [pend_len]
    lea rax, [rbx + rcx]
    cmp rax, r12
    jae .unfollowed
    cmp byte [rax], ':'
    jne .unfollowed
    mov rdi, rbx
    mov rdx, [pend_name]
    mov rsi, r12
    call has_prefix
    jne .unfollowed
    mov rax, [funcs_n]
    cmp rax, MAX_FUNCS
    jae fail_full
    mov rcx, [pend_name]
    lea rdx, [func_name]
    mov [rdx + rax * 8], rcx
    mov rcx, [pend_len]
    lea rdx, [func_len]
    mov [rdx + rax * 8], rcx
    mov rcx, [pend_file]
    lea rdx, [func_file]
    mov [rdx + rax * 8], rcx
    mov rcx, [pend_off]
    lea rdx, [func_off]
    mov [rdx + rax * 8], rcx
    movzx ecx, byte [pend_patch]
    lea rdx, [func_patch]
    mov [rdx + rax], cl
    inc qword [funcs_n]
    mov byte [pend_on], 0
    jmp .done
.unfollowed:
    mov rdi, [cur_file]
    mov rsi, [cur_no]
    call err_where
    lea rdi, [msg_header]
    call err_s
    mov rdi, [pend_name]
    mov rsi, [pend_len]
    call err_m
    lea rdi, [msg_unfollowed]
    call err_s
    jmp fail
.done:
    pop r13
    pop r12
    pop rbx
    ret

; is_keyword(rdi = text, rsi = end): ZF=1 if a data or equ keyword starts
; the text and ends at a non-word character
is_keyword:
    push rbx
    lea rbx, [keywords]
.next:
    movzx ecx, byte [rbx]
    test ecx, ecx
    jz .no
    lea rdx, [rbx + 1]
    call has_prefix
    jne .skip
    lea rax, [rdi + rcx]
    cmp rax, rsi
    jae .yes
    movzx eax, byte [rax]
    call is_word
    jne .yes
.skip:
    lea rbx, [rbx + rcx + 1]
    jmp .next
.yes:
    xor eax, eax
    pop rbx
    ret
.no:
    or eax, 1
    pop rbx
    ret

