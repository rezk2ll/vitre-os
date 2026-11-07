; `crypto <primitive> <hex>...`: runs a crypto primitive on hex inputs and
; prints its output in hex, so tests can check it against RFC vectors.

CR_MAX equ 512                      ; bytes in an input

; name: cmd_crypto
; in:   rdi = "<primitive> <hex>..."
; out:  the primitive's output printed in hex, or a usage line
; clobbers: caller-saved
cmd_crypto:
    push rbx
    push r12
    mov rbx, rdi
    call cr_cut
    mov r12, rax                    ; r12 = the inputs
    mov rdi, rbx
    lea rsi, [rel cr_sha256]
    call str_eq
    je .sha256
.usage:
    lea rdi, [rel cr_msg_usage]
    call kputs
    jmp .done
.sha256:
    mov rdi, r12
    lea rsi, [rel cr_in]
    call cr_hex
    jc .usage
    mov r12, rax
    lea rdi, [rel cr_ctx]
    call sha256_init
    lea rdi, [rel cr_ctx]
    lea rsi, [rel cr_in]
    mov rdx, r12
    call sha256_update
    lea rdi, [rel cr_ctx]
    lea rsi, [rel cr_out]
    call sha256_final
    lea rdi, [rel cr_out]
    mov esi, 32
    call cr_print
.done:
    pop r12
    pop rbx
    ret

; name: cr_cut
; in:   rdi = string
; out:  its first word ended with a 0; rax = what follows it
; clobbers: rax, rdi
cr_cut:
    mov al, [rdi]
    test al, al
    jz .end
    inc rdi
    cmp al, ' '
    jne cr_cut
    mov byte [rdi - 1], 0
.end:
    mov rax, rdi
    ret

; name: cr_hex
; in:   rdi = hex digits ended by a space or 0, rsi = output of CR_MAX bytes
; out:  rax = bytes written, rdi after the space; CF=1 if a digit is
;       not hex, their count is odd, or there are too many
; clobbers: rax, rcx, rdx, rdi
cr_hex:
    xor eax, eax
.byte:
    movzx ecx, byte [rdi]
    test ecx, ecx
    jz .done
    inc rdi
    cmp ecx, ' '
    je .done
    call cr_digit
    jc .done
    mov edx, ecx
    shl edx, 4
    movzx ecx, byte [rdi]
    inc rdi
    call cr_digit
    jc .done
    or edx, ecx
    cmp eax, CR_MAX
    jae cr_digit.bad                ; CF=1 there
    mov [rsi + rax], dl
    inc eax
    jmp .byte
.done:
    ret

; name: cr_digit
; in:   ecx = character
; out:  ecx = its hex value; CF=1 if it is not a hex digit
; clobbers: rcx
cr_digit:
    sub ecx, '0'
    cmp ecx, 10
    jb .ok
    or ecx, 0x20                    ; 'A' to 'F' as 'a' to 'f'
    sub ecx, 'a' - '0'
    cmp ecx, 6
    jae .bad
    add ecx, 10
.ok:
    clc
    ret
.bad:
    stc
    ret

; name: cr_print
; in:   rdi = bytes, esi = count
; out:  them printed in hex, then a newline
; clobbers: caller-saved
cr_print:
    push rbx
    push r12
    mov rbx, rdi
    mov r12d, esi
.byte:
    test r12d, r12d
    jz .done
    movzx edi, byte [rbx]
    mov esi, 2
    call kput_hexn
    inc rbx
    dec r12d
    jmp .byte
.done:
    mov edi, 10
    call kputc
    pop r12
    pop rbx
    ret

cr_sha256    db "sha256", 0
cr_msg_usage db "usage: crypto sha256 <hex>", 10, 0

section .bss
alignb 8
cr_ctx resb SHA_CTX_SIZE
cr_in  resb CR_MAX
cr_out resb 64
section .text
