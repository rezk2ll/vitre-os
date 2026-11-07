; hello.asm: greets you. Try: run hello.asm, or run hello.asm Vitre
;
; A program starts at its first line with rdi = its arguments, and returns
; with ret. It can call any kernel function by name: kputs, kputc,
; shell_readline, task_create and the rest.

start:
    push rbx
    mov rbx, rdi
    lea rdi, [rel hello]
    call kputs
    cmp byte [rbx], 0
    jne .name
    lea rbx, [rel world]
.name:
    mov rdi, rbx
    call kputs
    lea rdi, [rel done]
    call kputs
    pop rbx
    ret

hello db "Hello, ", 0
world db "world", 0
done  db "! Vitre assembled this program itself.", 10, 0
