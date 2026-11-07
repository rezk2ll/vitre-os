; Glass panes: text on the 8x16 character grid, and the register, memory
; and stack panes of the task view. Registers that changed since the last
; draw are shown in the accent colour.

GL_ACCENT  equ 0x0088c0d0
GL_DIM     equ 0x00616e88
GL_CHANGED equ 0x00ebcb8b

; name: gl_text
; in:   edi = column, esi = row, rdx = string, ecx = foreground, r8d = background
; out:  eax = column after the text; it is cut at the right edge
; clobbers: caller-saved
gl_text:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
.char:
    movzx edx, byte [r13]
    test edx, edx
    jz .done
    cmp rbx, [rel kernel_console + CON_COLS]
    jae .done
    mov edi, ebx
    shl edi, 3
    mov esi, r12d
    shl esi, 4
    mov ecx, r14d
    mov r8d, r15d
    call fb_draw_glyph
    inc r13
    inc ebx
    jmp .char
.done:
    mov eax, ebx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: gl_hex
; in:   edi = column, esi = row, rdx = value, ecx = digits, r8d = foreground
; out:  the low digits of the value drawn; eax = column after them
; clobbers: caller-saved
gl_hex:
    lea rax, [rel gl_hex_buf]
    mov byte [rax + rcx], 0
.digit:
    dec ecx
    js .draw
    mov r9d, edx
    and r9d, 15
    lea r10, [rel hex_digits]
    mov r9b, [r10 + r9]
    mov [rax + rcx], r9b
    shr rdx, 4
    jmp .digit
.draw:
    mov rdx, rax
    mov ecx, r8d
    mov r8d, COLOR_BG
    jmp gl_text

; name: gl_fill
; in:   edi = column, esi = row, edx = width in columns, ecx = colour
; out:  that run of cells filled, cut at the right edge
; clobbers: caller-saved
gl_fill:
    mov rax, [rel kernel_console + CON_COLS]
    sub rax, rdi
    jbe .done
    cmp rdx, rax
    cmova rdx, rax
    mov r8d, ecx
    shl edi, 3
    shl esi, 4
    shl edx, 3
    mov ecx, FONT_HEIGHT
    jmp fb_fill_rect
.done:
    ret

; name: gl_regs
; in:   edi = column, esi = row, rdx = interrupt frame
; out:  one "RAX=value" line per register; changed values in GL_CHANGED
; clobbers: caller-saved
gl_regs:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    mov r14, rdx
    xor ebx, ebx
.reg:
    lea rdx, [rel exc_reg_names]
    lea rdx, [rdx + rbx * 8]
    mov edi, r12d
    lea esi, [r13 + rbx]
    mov ecx, GL_DIM
    mov r8d, COLOR_BG
    call gl_text
    lea rcx, [rel exc_reg_offsets]
    movzx ecx, byte [rcx + rbx]
    mov rdx, [r14 + rcx]
    lea rcx, [rel gl_prev_regs]
    mov r8d, COLOR_FG
    cmp rdx, [rcx + rbx * 8]
    je .same
    mov r8d, GL_CHANGED
    mov [rcx + rbx * 8], rdx
.same:
    lea edi, [r12 + 5]
    lea esi, [r13 + rbx]
    mov ecx, 16
    call gl_hex
    inc ebx
    cmp ebx, EXC_REG_COUNT
    jb .reg
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: gl_regs_reset
; in:   rdi = interrupt frame
; out:  the frame becomes the "unchanged" baseline for gl_regs
; clobbers: rax, rcx, rdx
gl_regs_reset:
    xor ecx, ecx
.reg:
    lea rax, [rel exc_reg_offsets]
    movzx eax, byte [rax + rcx]
    mov rdx, [rdi + rax]
    lea rax, [rel gl_prev_regs]
    mov [rax + rcx * 8], rdx
    inc ecx
    cmp ecx, EXC_REG_COUNT
    jb .reg
    ret

; name: gl_memory
; in:   edi = column, esi = row, rdx = address, ecx = lines
; out:  8 bytes per line: address, hex bytes, then the bytes as text
; clobbers: caller-saved
gl_memory:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov r14d, ecx
.line:
    mov edi, r12d
    mov esi, r13d
    mov rdx, rbx
    mov ecx, 16
    mov r8d, GL_DIM
    call gl_hex
    xor r15d, r15d
.byte:
    lea edi, [r12 + 18 + r15 * 2]
    add edi, r15d
    mov esi, r13d
    movzx edx, byte [rbx + r15]
    mov ecx, 2
    mov r8d, COLOR_FG
    call gl_hex
    movzx eax, byte [rbx + r15]
    cmp eax, ' '
    jb .dot
    cmp eax, '~'
    jbe .char
.dot:
    mov eax, '.'
.char:
    lea rdx, [rel gl_hex_buf]
    mov [rdx], al
    mov byte [rdx + 1], 0
    lea edi, [r12 + 43 + r15]
    mov esi, r13d
    mov ecx, GL_ACCENT
    mov r8d, COLOR_BG
    call gl_text
    inc r15d
    cmp r15d, 8
    jb .byte
    add rbx, 8
    inc r13d
    dec r14d
    jnz .line
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: gl_stack
; in:   edi = column, esi = row, rdx = stack pointer, ecx = lines
; out:  one qword per line: its offset from the stack pointer, the value,
;       and the function it points into when it is a code address
; clobbers: caller-saved
gl_stack:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov r14d, ecx
    xor r15d, r15d
.line:
    mov edi, r12d
    mov esi, r13d
    mov rdx, r15
    mov ecx, 4
    mov r8d, GL_DIM
    call gl_hex
    lea rax, [rel gl_line]          ; value, and <function+offset> if any
    mov [rel dis_out], rax
    mov rdi, [rbx + r15]
    call dis_target
    mov rax, [rel dis_out]
    mov byte [rax], 0
    lea edi, [r12 + 6]
    mov esi, r13d
    lea rdx, [rel gl_line]
    mov ecx, COLOR_FG
    mov r8d, COLOR_BG
    call gl_text
    add r15d, 8
    inc r13d
    dec r14d
    jnz .line
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .bss
alignb 8
gl_prev_regs resq EXC_REG_COUNT
gl_hex_buf   resb 17
gl_line      resb DIS_LINE_MAX
section .text
