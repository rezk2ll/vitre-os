; `crypto <primitive> <hex>...`: runs a crypto primitive on hex inputs and
; prints its output in hex, so tests can check it against RFC vectors.

CR_MAX  equ HKDF_INFO_MAX           ; bytes in an input, so any info fits
CR_ARGS equ 4

; name: cmd_crypto
; in:   rdi = "<primitive> <hex>...", "-" standing for an empty input
; out:  the primitive's output printed in hex, or a usage line
; clobbers: caller-saved
cmd_crypto:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call cr_cut
    mov rdi, rax
    call cr_args
    jc .usage
    mov r12d, eax
    lea r13, [rel cr_table]
.find:
    mov rsi, [r13]
    test rsi, rsi
    jz .usage
    mov rdi, rbx
    call str_eq
    jne .skip
    cmp r12, [r13 + 16]
    jne .usage
    call [r13 + 8]
    jmp .done
.skip:
    add r13, 24
    jmp .find
.usage:
    lea rdi, [rel cr_msg_usage]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

cr_sha256:
    lea rdi, [rel cr_ctx]
    call sha256_init
    lea rdi, [rel cr_ctx]
    lea rsi, [rel cr_arg]
    mov edx, [rel cr_lens]
    call sha256_update
    lea rdi, [rel cr_ctx]
    lea rsi, [rel cr_out]
    call sha256_final
    mov esi, 32
    jmp cr_print_out

cr_hmac:                            ; key, message
    lea rdi, [rel cr_arg]
    mov esi, [rel cr_lens]
    lea rdx, [rel cr_arg + CR_MAX]
    mov ecx, [rel cr_lens + 4]
    lea r8, [rel cr_out]
    call hmac_sha256
    mov esi, 32
    jmp cr_print_out

cr_hkdf:                            ; salt, input key, info, one-byte length
    lea rdi, [rel cr_arg]
    mov esi, [rel cr_lens]
    lea rdx, [rel cr_arg + CR_MAX]
    mov ecx, [rel cr_lens + 4]
    lea r8, [rel cr_prk]
    call hmac_sha256
    lea rdi, [rel cr_prk]
    lea rsi, [rel cr_arg + 2 * CR_MAX]
    mov edx, [rel cr_lens + 8]
    lea rcx, [rel cr_out]
    movzx r8d, byte [rel cr_arg + 3 * CR_MAX]
    call hkdf_expand
    movzx esi, byte [rel cr_arg + 3 * CR_MAX]
    jmp cr_print_out

cr_chacha20:                        ; key, nonce, one-byte counter, data
    lea rdi, [rel cr_arg]
    movzx esi, byte [rel cr_arg + 2 * CR_MAX]
    lea rdx, [rel cr_arg + CR_MAX]
    lea rcx, [rel cr_arg + 3 * CR_MAX]
    mov r8d, [rel cr_lens + 12]
    lea r9, [rel cr_out]
    call chacha20_xor
    mov esi, [rel cr_lens + 12]
cr_print_out:
    lea rdi, [rel cr_out]
    jmp cr_print

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

; name: cr_args
; in:   rdi = hex inputs separated by spaces
; out:  them decoded into cr_arg, their lengths in cr_lens; eax = count;
;       CF=1 if one is not hex or there are more than CR_ARGS
; clobbers: rax, rcx, rdx, rsi, rdi
cr_args:
    push rbx
    xor ebx, ebx
.next:
    cmp byte [rdi], 0
    je .done                        ; CF=0 here
    cmp ebx, CR_ARGS
    jae .bad
    imul esi, ebx, CR_MAX
    lea rax, [rel cr_arg]
    add rsi, rax
    call cr_hex
    jc .bad
    lea rcx, [rel cr_lens]
    mov [rcx + rbx * 4], eax
    inc ebx
    jmp .next
.done:
    mov eax, ebx
    pop rbx
    ret
.bad:
    stc
    pop rbx
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
    cmp ecx, '-'                    ; how an empty input is written
    je .byte
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

cr_table:
    dq cr_n_sha256, cr_sha256, 1
    dq cr_n_hmac, cr_hmac, 2
    dq cr_n_hkdf, cr_hkdf, 4
    dq cr_n_chacha20, cr_chacha20, 4
    dq 0

cr_n_sha256   db "sha256", 0
cr_n_hmac     db "hmac", 0
cr_n_hkdf     db "hkdf", 0
cr_n_chacha20 db "chacha20", 0
cr_msg_usage db "usage: crypto sha256 <data> | hmac <key> <data> | hkdf <salt> <key> <info> <len>", 10
             db "       | chacha20 <key> <nonce> <counter> <data>", 10
             db "       inputs in hex, - for an empty one", 10, 0

section .bss
alignb 8
cr_lens resd CR_ARGS
cr_ctx  resb SHA_CTX_SIZE
cr_prk  resb 32
cr_arg  resb CR_ARGS * CR_MAX
cr_out  resb CR_MAX
section .text
