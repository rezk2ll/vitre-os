; name: str_eq
; in:   rdi, rsi = zero-terminated strings
; out:  ZF=1 if equal
; clobbers: rax, rdi, rsi
str_eq:
.next:
    mov al, [rdi]
    cmp al, [rsi]
    jne .done
    test al, al
    jz .done
    inc rdi
    inc rsi
    jmp .next
.done:
    ret

; name: str_skip
; in:   rdi = zero-terminated string
; out:  rax = the byte after its terminator
; clobbers: none
str_skip:
    mov rax, rdi
.next:
    inc rax
    cmp byte [rax - 1], 0
    jne .next
    ret

; name: str_has_word
; in:   rdi = word, rsi = space-separated words (both zero-terminated)
; out:  ZF=1 if the word is one of the words
; clobbers: rax, rcx, rdx, rsi
str_has_word:
.word:
    xor ecx, ecx
.cmp:
    mov al, [rdi + rcx]
    mov dl, [rsi + rcx]
    test al, al
    jz .word_end
    cmp al, dl
    jne .skip
    inc rcx
    jmp .cmp
.word_end:
    test dl, dl
    jz .found
    cmp dl, ' '
    je .found
.skip:
    mov al, [rsi]
    test al, al
    jz .missing
    inc rsi
    cmp al, ' '
    jne .skip
    jmp .word
.found:
    ret                             ; ZF=1 from the test/cmp above
.missing:
    or eax, 1                       ; ZF=0
    ret
