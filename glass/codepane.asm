; Glass code pane: the instructions around RIP, and the function and
; source module holding an address.

GL_TOP        equ 2                 ; first pane row, under the title and a header
GL_CODE_COL   equ 28
GL_CODE_ABOVE equ 4                 ; instructions shown before RIP
GL_RIP_BG     equ 0x00434c5e

; name: gl_code
; in:   rdi = RIP
; out:  EXC_REG_COUNT instructions in the code pane, starting a few before
;       RIP when its function can be decoded from the top; RIP's line is
;       highlighted
; clobbers: caller-saved
gl_code:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rbx, rdi                    ; first line shown
    call gl_function_start
    jc .draw
    xor r13d, r13d                  ; instructions decoded
.decode:
    cmp rax, r12
    jae .landed
    lea rcx, [rel gl_recent]
    mov edx, r13d
    and edx, GL_CODE_ABOVE - 1
    mov [rcx + rdx * 8], rax
    inc r13d
    mov r14, rax
    mov rdi, rax
    lea rsi, [rel gl_line]
    call dis_one
    add rax, r14
    jmp .decode
.landed:
    jne .draw                       ; RIP is not on an instruction boundary
    cmp r13d, GL_CODE_ABOVE
    jb .from_start
    mov edx, r13d                   ; oldest of the last GL_CODE_ABOVE
    and edx, GL_CODE_ABOVE - 1
    lea rcx, [rel gl_recent]
    mov rbx, [rcx + rdx * 8]
    jmp .draw
.from_start:
    test r13d, r13d
    jz .draw
    lea rcx, [rel gl_recent]
    mov rbx, [rcx]
.draw:
    xor r13d, r13d
.line:
    mov edi, GL_CODE_COL
    lea esi, [r13 + GL_TOP]
    mov edx, 1000
    mov ecx, COLOR_BG
    cmp rbx, r12
    jne .clear
    mov ecx, GL_RIP_BG
.clear:
    mov r15d, ecx
    call gl_fill
    mov edi, GL_CODE_COL
    lea esi, [r13 + GL_TOP]
    mov rdx, rbx
    mov ecx, 16
    mov r8d, GL_DIM
    call gl_hex
    mov rdi, rbx
    lea rsi, [rel gl_line]
    call dis_one
    add rbx, rax
    mov edi, GL_CODE_COL + 18
    lea esi, [r13 + GL_TOP]
    lea rdx, [rel gl_line]
    mov ecx, COLOR_FG
    mov r8d, r15d
    call gl_text
    inc r13d
    cmp r13d, EXC_REG_COUNT
    jb .line
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: gl_function_start
; in:   rdi = code address
; out:  rax = start of the function holding it, rdx = its symbol record;
;       CF=1 if no symbol does
; clobbers: rax, rcx, rdx
gl_function_start:
    lea rdx, [rel sym_table]
    mov ecx, SYM_COUNT
.symbol:
    mov rax, rdi
    sub rax, [rdx + SYM_ADDR]
    jb .next
    cmp rax, [rdx + SYM_SIZE]
    jb .found
.next:
    add rdx, SYM_RECORD
    dec ecx
    jnz .symbol
    stc
    ret
.found:
    mov rax, [rdx + SYM_ADDR]
    clc
    ret

; name: gl_module_of
; in:   rdi = code address
; out:  rax = path of the source area module holding its function; CF=1 if
;       the function is not in a module
; clobbers: rax, rcx, rdx, rsi
gl_module_of:
    call gl_function_start
    jc .none
    movsxd rsi, dword [rdx + SYM_SRC]
    test rsi, rsi
    js .none
    mov rax, [rel src_area]
    test rax, rax
    jz .none
    mov ecx, [rax + SRC_HDR_COUNT]
    test ecx, ecx
    jz .none
    lea rdx, [rax + SRC_DIR]
.module:
    mov eax, [rdx + SRC_DIR_START]
    cmp rsi, rax
    jb .next_module
    add eax, [rdx + SRC_DIR_LEN]
    cmp rsi, rax
    jae .next_module
    mov rax, rdx
    clc
    ret
.next_module:
    add rdx, SRC_DIR_ENTRY
    dec ecx
    jnz .module
.none:
    stc
    ret

section .bss
alignb 8
gl_recent resq GL_CODE_ABOVE
section .text
