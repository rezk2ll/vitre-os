; Text scanning for tools/gen.asm.

; streq(rdi, rsi = strings): ZF=1 if equal, else the flags of comparing the
; first differing bytes
streq:
    xor ecx, ecx
.next:
    mov al, [rdi + rcx]
    cmp al, [rsi + rcx]
    jne .ret
    inc rcx
    test al, al
    jnz .next
.ret:
    ret

; has_prefix(rdi = text, rsi = its end, rdx = prefix, rcx = its length):
; ZF=1 if the text starts with the prefix. Keeps every register but rax, r8
has_prefix:
    lea rax, [rdi + rcx]
    cmp rax, rsi
    ja .no
    xor r8d, r8d
.next:
    cmp r8, rcx
    je .yes
    mov al, [rdi + r8]
    cmp al, [rdx + r8]
    jne .no
    inc r8
    jmp .next
.yes:
    cmp eax, eax
    ret
.no:
    or eax, 1
    ret

; skip_space(rdi = text, rsi = end): rax = the first non-space. Keeps
; every other register
skip_space:
    mov rax, rdi
.next:
    cmp rax, rsi
    jae .ret
    cmp byte [rax], ' '
    je .space
    cmp byte [rax], 9
    jb .ret
    cmp byte [rax], 13              ; \t \n \v \f \r
    ja .ret
.space:
    inc rax
    jmp .next
.ret:
    ret

; word_len(rdi = text, rsi = end): rax = length of the run of word
; characters (letters, digits, _) it starts with. Keeps every other register
word_len:
    push rcx
    xor ecx, ecx
.next:
    lea rax, [rdi + rcx]
    cmp rax, rsi
    jae .ret
    movzx eax, byte [rax]
    call is_word
    jne .ret
    inc rcx
    jmp .next
.ret:
    mov rax, rcx
    pop rcx
    ret

; is_word(eax = byte): ZF=1 if it is a letter, digit or _. Keeps the rest
is_word:
    push rax
    cmp al, '_'
    je .yes
    sub al, '0'
    cmp al, 9
    jbe .yes
    add al, '0'
    or al, 0x20
    sub al, 'a'
    cmp al, 25
    jbe .yes
    pop rax
    test rsp, rsp                   ; ZF=0
    ret
.yes:
    pop rax
    cmp eax, eax
    ret

