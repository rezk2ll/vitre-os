; Files, the output buffer and error messages for tools/gen.asm.


ARENA_SIZE equ 1 << 26
OUT_SIZE   equ 1 << 23

; load_file(rdi = path): rax = its text in the arena, rdx = its length
load_file:
    push rbx
    push r12
    mov rbx, rdi
    xor esi, esi
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .missing
    mov r12, rax
    mov rsi, [arena_ptr]
    push rsi
.read:
    lea rdx, [arena + ARENA_SIZE]
    sub rdx, rsi
    jz fail_full
    mov rdi, r12
    xor eax, eax                    ; SYS_READ
    push rsi
    syscall
    pop rsi
    test rax, rax
    js .missing
    jz .eof
    add rsi, rax
    jmp .read
.eof:
    mov [arena_ptr], rsi
    mov rdi, r12
    mov eax, SYS_CLOSE
    syscall
    pop rax
    mov rdx, [arena_ptr]
    sub rdx, rax
    pop r12
    pop rbx
    ret
.missing:
    lea rdi, [msg_cannot]
    call err_s
    mov rdi, rbx
    call err_s
    mov edi, 10
    call err_c
    jmp fail

; mkdir(rdi = path): created, or left as it is
mkdir:
    mov esi, 0o755
    mov eax, SYS_MKDIR
    syscall
    ret

; out_reset: empties the output buffer
out_reset:
    lea rax, [out_buf]
    mov [out_ptr], rax
    ret

; out_s(rdi = string): appended to the output
out_s:
    mov rsi, rdi
.len:
    cmp byte [rsi], 0
    je .got
    inc rsi
    jmp .len
.got:
    sub rsi, rdi
    jmp out_m

; out_m(rdi = text, rsi = length): appended to the output
out_m:
    mov rcx, rsi
    mov rsi, rdi
    mov rdi, [out_ptr]
    lea rax, [rdi + rcx]
    lea rdx, [out_buf + OUT_SIZE]
    cmp rax, rdx
    ja fail_full
    rep movsb
    mov [out_ptr], rdi
    ret

; out_c(edi = byte): appended to the output
out_c:
    mov rax, [out_ptr]
    mov [rax], dil
    inc qword [out_ptr]
    ret

; out_dec(rdi = signed value): appended in decimal
out_dec:
    sub rsp, 32
    lea rsi, [rsp + 32]
    mov rax, rdi
    test rax, rax
    jns .digits
    neg rax
.digits:
    xor edx, edx
    mov ecx, 10
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digits
    test rdi, rdi
    jns .write
    dec rsi
    mov byte [rsi], '-'
.write:
    mov rdi, rsi
    lea rsi, [rsp + 32]
    sub rsi, rdi
    call out_m
    add rsp, 32
    ret

; out_write(rdi = path): the output written to the file, unless the file
; already holds exactly that
out_write:
    lea rsi, [out_buf]
    mov rdx, [out_ptr]
    sub rdx, rsi
    jmp write_if_changed

; write_if_changed(rdi = path, rsi = data, rdx = length)
write_if_changed:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor esi, esi
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .write
    mov r14, rax
    lea rsi, [cmp_buf]
.read:
    lea rdx, [cmp_buf + OUT_SIZE]
    sub rdx, rsi
    jz .close
    mov rdi, r14
    xor eax, eax                    ; SYS_READ
    push rsi
    syscall
    pop rsi
    test rax, rax
    jle .close
    add rsi, rax
    jmp .read
.close:
    push rsi
    mov rdi, r14
    mov eax, SYS_CLOSE
    syscall
    pop rsi
    lea rax, [cmp_buf]
    sub rsi, rax
    cmp rsi, r13
    jne .write
    xor ecx, ecx
.cmp:
    cmp rcx, r13
    je .done
    mov al, [r12 + rcx]
    cmp al, [cmp_buf + rcx]
    jne .write
    inc rcx
    jmp .cmp
.write:
    mov rdi, rbx
    mov esi, O_WRONLY_CREAT_TRUNC
    mov edx, 0o644
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .fail
    mov r14, rax
.chunk:
    test r13, r13
    jz .written
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle .fail
    add r12, rax
    sub r13, rax
    jmp .chunk
.written:
    mov rdi, r14
    mov eax, SYS_CLOSE
    syscall
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    lea rdi, [msg_cannot_write]
    call err_s
    mov rdi, rbx
    call err_s
    mov edi, 10
    call err_c
    jmp fail

; err_s(rdi = string), err_m(rdi = text, rsi = length), err_c(edi = byte),
; err_dec(rdi = value): written to stderr
err_s:
    mov rsi, rdi
.len:
    cmp byte [rsi], 0
    je .got
    inc rsi
    jmp .len
.got:
    sub rsi, rdi
err_m:
    mov rdx, rsi
    mov rsi, rdi
    mov edi, 2
    mov eax, SYS_WRITE
    syscall
    ret

err_c:
    push rdi
    mov rdi, rsp
    mov esi, 1
    call err_m
    pop rdi
    ret

err_dec:
    push rbx
    mov rbx, [out_ptr]
    call out_dec
    mov rdi, rbx
    mov rsi, [out_ptr]
    sub rsi, rbx
    mov [out_ptr], rbx
    call err_m
    pop rbx
    ret

; err_where(rdi = file index, rsi = line number): "path:no: " on stderr
err_where:
    push rbx
    mov rbx, rsi
    lea rax, [file_path]
    mov rdi, [rax + rdi * 8]
    call err_s
    mov edi, ':'
    call err_c
    mov rdi, rbx
    call err_dec
    mov edi, ':'
    call err_c
    mov edi, ' '
    call err_c
    pop rbx
    ret

fail_full:
    lea rdi, [msg_full]
    call err_s
fail:
    mov edi, 1
    mov eax, SYS_EXIT
    syscall

section .data
arena_ptr        dq arena
out_ptr          dq out_buf
msg_cannot       db "gen: cannot read ", 0
msg_cannot_write db "gen: cannot write ", 0
msg_full         db "gen: out of room, raise a limit in tools/gen.asm", 10, 0

section .bss
alignb 16
arena   resb ARENA_SIZE
out_buf resb OUT_SIZE
cmp_buf resb OUT_SIZE
section .text
