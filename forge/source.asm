; Source area in memory: a header ("VSRC", file count, total length), a
; directory of SRC_FILES_MAX 48-byte entries (path, offset and length from
; the start of the area, flags), then the file texts back to back. The
; directory has a fixed size so that adding a file moves no text: symbol
; records hold offsets into the kernel modules.

SRC_HDR_COUNT equ 4
SRC_DIR       equ 16
SRC_DIR_ENTRY equ 48
SRC_DIR_START equ 32
SRC_DIR_LEN   equ 36
SRC_DIR_FLAGS equ 40
SRC_FILES_MAX equ 64                ; as in tools/gensrc.asm
SRC_TEXT      equ SRC_DIR + SRC_FILES_MAX * SRC_DIR_ENTRY
SRC_NAME_MAX  equ 31

SRC_EDITED equ 1                    ; a kernel module boot patches from here
SRC_FILE   equ 2                    ; a user file, not part of the kernel

; name: src_find
; in:   rdi = module path, e.g. "kernel/report.asm"
; out:  rax = its text, rdx = its length, rcx = its directory entry; CF=1 if
;       the source area has no such module
; clobbers: rsi, rdi
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
    mov rcx, rbx
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
    mov rbx, [rel src_area]
    sub rcx, rbx
    mov [rsp], rcx                  ; its entry, as an offset in the area
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
    add [rsp], r14
    mov ecx, SRC_TEXT
    mov rbp, rcx                    ; rbp = where the next text goes
    mov rsi, rbx
    mov rdi, r14
    rep movsb
    mov [r14 + SRC_HDR_LENGTH], r15d
    lea r8, [r14 + SRC_DIR]
    mov r9d, [r14 + SRC_HDR_COUNT]
    imul r9d, r9d, SRC_DIR_ENTRY
    add r9, r8
.file:
    cmp r8, r9
    jae .copied
    mov esi, [r8 + SRC_DIR_START]
    add rsi, rbx
    mov ecx, [r8 + SRC_DIR_LEN]
    cmp r8, [rsp]
    jne .copy
    mov rsi, r12
    mov rcx, r13
    test dword [r8 + SRC_DIR_FLAGS], SRC_FILE
    jnz .copy
    mov dword [r8 + SRC_DIR_FLAGS], SRC_EDITED
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

; name: src_add
; in:   rdi = path
; out:  an empty user file of that path at the end of the directory; CF=1 if
;       the path is empty, too long or taken, or the directory is full
; clobbers: caller-saved
src_add:
    push rbx
    mov rbx, rdi
    call src_find
    jnc .fail
    mov rdx, [rel src_area]
    test rdx, rdx
    jz .fail
    mov eax, [rdx + SRC_HDR_COUNT]
    cmp eax, SRC_FILES_MAX
    jae .fail
    imul eax, eax, SRC_DIR_ENTRY
    lea rdi, [rdx + SRC_DIR + rax]
    mov rsi, rbx
    xor ecx, ecx
.name:
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .named
    inc ecx
    cmp ecx, SRC_NAME_MAX
    jbe .name
    jmp .fail
.named:
    test ecx, ecx
    jz .fail
    mov rax, [rel src_length]
    mov [rdi + SRC_DIR_START], eax
    mov dword [rdi + SRC_DIR_LEN], 0
    mov qword [rdi + SRC_DIR_FLAGS], SRC_FILE
    inc dword [rdx + SRC_HDR_COUNT]
    pop rbx
    clc
    ret
.fail:
    pop rbx
    stc
    ret

; name: src_remove
; in:   rdi = path of a user file
; out:  the file and its directory entry gone; CF=1 if there is no such user
;       file
; clobbers: caller-saved
src_remove:
    push rbx
    mov rbx, rdi
    call src_find
    jc .fail
    test dword [rcx + SRC_DIR_FLAGS], SRC_FILE
    jz .fail
    mov rdi, rbx
    xor edx, edx
    call src_replace                ; its text gone; the area moved
    jc .fail
    mov rdi, rbx
    call src_find
    mov rdi, rcx                    ; the entries after it move down one
    lea rsi, [rcx + SRC_DIR_ENTRY]
    mov rdx, [rel src_area]
    mov ecx, [rdx + SRC_HDR_COUNT]
    imul ecx, ecx, SRC_DIR_ENTRY
    lea rcx, [rdx + SRC_DIR + rcx]
    sub rcx, rsi
    rep movsb
    dec dword [rdx + SRC_HDR_COUNT]
    pop rbx
    clc
    ret
.fail:
    pop rbx
    stc
    ret
