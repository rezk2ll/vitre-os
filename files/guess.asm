; guess.asm: find the number between 1 and 100. Try: run guess.asm
; An empty line gives up.

start:
    push rbx
    push r12
    push r13
    mov rax, [rel timer_ticks]
    xor edx, edx
    mov ecx, 100
    div rcx
    lea rbx, [rdx + 1]
    xor r12d, r12d
    lea rdi, [rel intro]
    call kputs
.ask:
    lea rdi, [rel prompt]
    call kputs
    lea rdi, [rel line]
    call shell_readline
    cmp byte [rel line], 0
    je .quit
    lea rsi, [rel line]
    xor eax, eax
.digit:
    movzx ecx, byte [rsi]
    sub ecx, '0'
    cmp ecx, 9
    ja .parsed
    imul eax, 10
    add eax, ecx
    inc rsi
    jmp .digit
.parsed:
    inc r12d
    cmp eax, ebx
    je .won
    lea rdi, [rel higher]
    jb .say
    lea rdi, [rel lower]
.say:
    call kputs
    jmp .ask
.won:
    lea rdi, [rel won]
    call kputs
    mov edi, r12d
    call [rel jt_kput_dec]
    lea rdi, [rel tries]
    call kputs
    jmp .done
.quit:
    lea rdi, [rel gave_up]
    call kputs
    mov edi, ebx
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
.done:
    pop r13
    pop r12
    pop rbx
    ret

intro   db "I picked a number between 1 and 100.", 10, 0
prompt  db "guess: ", 0
higher  db "higher", 10, 0
lower   db "lower", 10, 0
won     db "yes! found in ", 0
tries   db " tries", 10, 0
gave_up db "it was ", 0
line    db 0
        times 1023 db 0
