; Source area in memory: a header ("VSRC", file count, total length), a
; directory of 48-byte entries (path, then offset and length from the start
; of the area), then the file texts back to back.

SRC_HDR_COUNT equ 4
SRC_DIR       equ 16
SRC_DIR_ENTRY equ 48
SRC_DIR_START equ 32
SRC_DIR_LEN   equ 36

; name: src_find
; in:   rdi = module path, e.g. "kernel/report.asm"
; out:  rax = its text, rdx = its length; CF=1 if the source area has no such
;       module
; clobbers: rcx, rsi, rdi
src_find:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, [rel src_area]
    test rbx, rbx
    jz .missing
    mov r13d, [rbx + SRC_HDR_COUNT]
    lea rbx, [rbx + SRC_DIR]
.entry:
    test r13d, r13d
    jz .missing
    mov rdi, r12
    mov rsi, rbx
    call str_eq
    je .found
    add rbx, SRC_DIR_ENTRY
    dec r13d
    jmp .entry
.found:
    mov eax, [rbx + SRC_DIR_START]
    add rax, [rel src_area]
    mov edx, [rbx + SRC_DIR_LEN]
    pop r13
    pop r12
    pop rbx
    clc
    ret
.missing:
    pop r13
    pop r12
    pop rbx
    stc
    ret

; name: src_replace
; in:   rdi = module path, rsi = new text, rdx = its length
; out:  the source area rebuilt with that module's text replaced; CF=1 if
;       the module is missing, memory is short or the area would not fit on
;       disk
; clobbers: caller-saved
src_replace:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24
    mov r12, rsi
    mov r13, rdx
    call src_find
    jc .fail
    mov [rsp], rax                  ; old text, to recognise its entry
    mov rbx, [rel src_area]
    mov r15, [rel src_length]
    sub r15, rdx
    add r15, r13
    cmp r15, SRC_SECTORS * 512
    ja .fail
    lea rdi, [r15 + PAGE_SIZE - 1]
    shr rdi, 12
    call page_alloc
    jc .fail
    mov r14, rax
    mov ecx, [rbx + SRC_HDR_COUNT]
    imul ecx, SRC_DIR_ENTRY
    add ecx, SRC_DIR
    mov rbp, rcx                    ; rbp = where the next text goes
    mov rsi, rbx
    mov rdi, r14
    rep movsb
    mov [r14 + SRC_HDR_LENGTH], r15d
    lea r8, [r14 + SRC_DIR]
    lea r9, [r14 + rbp]
.file:
    cmp r8, r9
    jae .copied
    mov esi, [r8 + SRC_DIR_START]
    add rsi, rbx
    mov ecx, [r8 + SRC_DIR_LEN]
    cmp rsi, [rsp]
    jne .copy
    mov rsi, r12
    mov rcx, r13
.copy:
    mov [r8 + SRC_DIR_START], ebp
    mov [r8 + SRC_DIR_LEN], ecx
    lea rdi, [r14 + rbp]
    add rbp, rcx
    rep movsb
    add r8, SRC_DIR_ENTRY
    jmp .file
.copied:
    mov rdi, rbx
    mov rsi, [rel src_length]
    add rsi, PAGE_SIZE - 1
    shr rsi, 12
    call page_free
    mov [rel src_area], r14
    mov [rel src_length], r15
    clc
    jmp .return
.fail:
    stc
.return:
    lea rsp, [rsp + 24]             ; keeps CF
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
