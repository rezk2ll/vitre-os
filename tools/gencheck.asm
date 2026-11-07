; Direct-call check for tools/gen.asm: a patchable function is called
; through its jump table slot, never directly, or a live patch would miss
; the call.

; check_calls: fails the build on any `call x` or `jcc x` outside
; comments where x is a patchable function
check_calls:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    xor r15d, r15d                  ; file index
.file:
    cmp r15, [files_n]
    jae .files_done
    lea rax, [file_text]
    mov r12, [rax + r15 * 8]
    lea rax, [file_len]
    mov r13, [rax + r15 * 8]
    add r13, r12
    xor ebx, ebx
.line:
    cmp r12, r13
    jae .next_file
    inc rbx
    mov rdi, r12
    mov rsi, r13
    call line_end
    mov [line_next], rax
    mov rbp, r12                    ; code end: the first ';' or the line end
.code:
    cmp rbp, rax
    jae .scan
    cmp byte [rbp], ';'
    je .scan
    inc rbp
    jmp .code
.scan:
    mov r14, r12
.at:
    cmp r14, rbp
    jae .line_done
    cmp r14, r12
    je .start
    movzx eax, byte [r14 - 1]
    call is_word
    je .step
.start:
    mov rdi, r14
    mov rsi, rbp
    lea rdx, [kw_call]
    mov ecx, 4
    call has_prefix
    lea rdi, [r14 + 4]
    je .space
    cmp byte [r14], 'j'
    jne .step
    lea rdi, [r14 + 1]
.letters:
    cmp rdi, rbp
    jae .letters_end
    movzx eax, byte [rdi]
    sub eax, 'a'
    cmp eax, 25
    ja .letters_end
    inc rdi
    jmp .letters
.letters_end:
    lea rax, [r14 + 1]
    cmp rdi, rax
    je .step
.space:
    mov rsi, rbp
    mov rdx, rdi
    call skip_space
    cmp rax, rdx
    je .step
    mov rdi, rax
    call word_len
    test rax, rax
    jz .step
    mov rsi, rax
    call patchable_index
    lea r14, [rdi + rsi]            ; findall goes on after the match
    js .at
    call report_direct
    jmp .at
.step:
    inc r14
    jmp .at
.line_done:
    mov r12, [line_next]
    jmp .line
.next_file:
    inc r15
    jmp .file
.files_done:
    cmp byte [direct_found], 0
    jne fail
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; report_direct(rdi = target, rsi = its length), at r15 = file, rbx = line
; number, r12 = line start: "path:no: direct 'line', use [rel jt_x]"
report_direct:
    push r12
    push r13
    push r14
    mov r13, rdi
    mov r14, rsi
    mov rdi, r15
    mov rsi, rbx
    call err_where
    lea rdi, [msg_direct]
    call err_s
    mov rdi, r12
    mov rsi, [line_next]
    call skip_space
    mov r12, rax
    mov rax, rsi
.trim:
    cmp rax, r12
    jbe .trimmed
    movzx ecx, byte [rax - 1]
    cmp ecx, ' '
    ja .trimmed
    dec rax
    jmp .trim
.trimmed:
    mov rdi, r12
    mov rsi, rax
    sub rsi, r12
    call err_m
    lea rdi, [msg_use]
    call err_s
    mov rdi, r13
    mov rsi, r14
    call err_m
    lea rdi, [msg_use_end]
    call err_s
    mov byte [direct_found], 1
    pop r14
    pop r13
    pop r12
    ret

; patchable_index(rdi = name, rsi = length): rax = its slot in the jump
; table, SF=1 if it is not a patchable function
; clobbers rax, rcx, rdx, r8, r9
patchable_index:
    xor r8d, r8d                    ; function
    xor r9d, r9d                    ; slot
.next:
    cmp r8, [funcs_n]
    jae .none
    lea rax, [func_patch]
    cmp byte [rax + r8], 0
    je .skip
    lea rax, [func_len]
    cmp [rax + r8 * 8], rsi
    jne .slot
    lea rax, [func_name]
    mov rdx, [rax + r8 * 8]
    xor ecx, ecx
.cmp:
    cmp rcx, rsi
    je .found
    mov al, [rdx + rcx]
    cmp al, [rdi + rcx]
    jne .slot
    inc rcx
    jmp .cmp
.slot:
    inc r9
.skip:
    inc r8
    jmp .next
.found:
    mov rax, r9
    test rax, rax                   ; SF=0
    ret
.none:
    or rax, -1
    ret


section .data

kw_call        db "call"

msg_direct     db "direct '", 0

msg_use        db "', use [rel jt_", 0

msg_use_end    db "]", 10, 0



section .bss

line_next    resq 1

direct_found resb 1

section .text
