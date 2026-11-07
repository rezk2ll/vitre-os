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
