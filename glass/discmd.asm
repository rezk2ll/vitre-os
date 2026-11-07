; Disassembler front ends: branch targets named by symbol, and the `dis`
; shell command.

; name: dis_target
; in:   rdi = branch target
; out:  its address appended, then "<function+offset>" when a symbol holds it
; clobbers: caller-saved
dis_target:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    call dis_hex
    lea rbx, [rel sym_table]
    mov ecx, SYM_COUNT
.symbol:
    mov rax, r12
    sub rax, [rbx + SYM_ADDR]
    jb .next
    cmp rax, [rbx + SYM_SIZE]
    jb .found
.next:
    add rbx, SYM_RECORD
    dec ecx
    jnz .symbol
    jmp .done
.found:
    push rax
    sub rsp, 8
    mov dil, ' '
    call dis_c
    mov dil, '<'
    call dis_c
    mov rax, [rel dis_out]
    xor ecx, ecx
.name:
    mov dl, [rbx + SYM_NAME + rcx]
    test dl, dl
    jz .named
    mov [rax + rcx], dl
    inc ecx
    cmp ecx, 32
    jb .name
.named:
    add [rel dis_out], rcx
    add rsp, 8
    pop rdi
    test rdi, rdi
    jz .close
    mov esi, 1
    call dis_signed
.close:
    mov dil, '>'
    call dis_c
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: cmd_dis
; in:   rdi = "<0xaddress|label> [count]"
; out:  count instructions (8 by default, at most 64) from there, one per line
; clobbers: caller-saved
cmd_dis:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r13d, 8
.word_end:
    mov al, [rdi]
    test al, al
    jz .address
    cmp al, ' '
    je .count
    inc rdi
    jmp .word_end
.count:
    mov byte [rdi], 0
    inc rdi
    call parse_dec
    jc .usage
    test rax, rax
    jz .usage
    mov r13d, 64
    cmp rax, r13
    cmovb r13d, eax
.address:
    mov rdi, rbx
    call parse_addr
    jc .usage
    mov r12, rax
.line:
    lea rdi, [rel shell_indent]
    call kputs
    mov rdi, r12
    call kput_hex
    lea rdi, [rel shell_indent]
    call kputs
    mov rdi, r12
    lea rsi, [rel dis_line]
    call dis_one
    add r12, rax
    lea rdi, [rel dis_line]
    call kputs
    mov edi, 10
    call kputc
    dec r13d
    jnz .line
    jmp .done
.usage:
    lea rdi, [rel dis_msg_usage]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

dis_msg_usage db "usage: dis <0xaddress|label> [count]", 10, 0

section .bss
dis_line resb DIS_LINE_MAX
section .text
