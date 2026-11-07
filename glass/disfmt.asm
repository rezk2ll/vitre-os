; Disassembler output: text, numbers, registers and ModRM operands, written
; at dis_out. Decoding state lives in .bss below and is reset per instruction.

REX_B equ 1
REX_X equ 2
REX_R equ 4
REX_W equ 8

; name: dis_c
; in:   dil = character
; out:  appended to the output
; clobbers: rax
dis_c:
    mov rax, [rel dis_out]
    mov [rax], dil
    inc qword [rel dis_out]
    ret

; name: dis_s
; in:   rdi = zero-terminated string
; out:  appended to the output
; clobbers: rax, rcx, rdi
dis_s:
    mov rax, [rel dis_out]
.char:
    mov cl, [rdi]
    test cl, cl
    jz .done
    mov [rax], cl
    inc rax
    inc rdi
    jmp .char
.done:
    mov [rel dis_out], rax
    ret

; name: dis_hex
; in:   rdi = value
; out:  "0x" and its hex digits without leading zeros appended
; clobbers: rax, rcx, rdx, rdi, rsi
dis_hex:
    mov rsi, rdi
    mov dil, '0'
    call dis_c
    mov dil, 'x'
    call dis_c
    mov ecx, 60
.skip:
    test ecx, ecx
    jz .digit
    mov rax, rsi
    shr rax, cl
    test al, 15
    jnz .digit
    sub ecx, 4
    jmp .skip
.digit:
    mov rax, rsi
    shr rax, cl
    and eax, 15
    lea rdx, [rel hex_digits]
    mov dil, [rdx + rax]
    call dis_c
    sub ecx, 4
    jns .digit
    ret

; name: dis_signed
; in:   rdi = value, esi = 1 to print "+" before a positive one
; out:  "-0x.." or "0x.." ("+0x.." with esi = 1) appended
; clobbers: rax, rcx, rdx, rdi, rsi
dis_signed:
    test rdi, rdi
    jns .positive
    neg rdi
    push rdi
    mov dil, '-'
    call dis_c
    pop rdi
    jmp dis_hex
.positive:
    test esi, esi
    jz dis_hex
    push rdi
    mov dil, '+'
    call dis_c
    pop rdi
    jmp dis_hex

; name: dis_comma
; in:   none
; out:  ", " appended
; clobbers: rax, rdi
dis_comma:
    mov dil, ','
    call dis_c
    mov dil, ' '
    jmp dis_c

; name: dis_reg
; in:   edi = register number 0-15, esi = size in bytes (1, 2, 4, 8)
; out:  its name appended; without REX, byte registers 4-7 are ah to bh
; clobbers: rax, rcx, rdi
dis_reg:
    lea rax, [rel dis_reg64]
    cmp esi, 8
    je .table
    lea rax, [rel dis_reg32]
    cmp esi, 4
    je .table
    lea rax, [rel dis_reg16]
    cmp esi, 2
    je .table
    lea rax, [rel dis_reg8]
    cmp byte [rel dis_rex], 0
    jne .table
    cmp edi, 4
    jb .table
    cmp edi, 8
    jae .table
    lea rax, [rel dis_reg8_high - 16]
.table:
    lea rax, [rax + rdi * 4]
    mov ecx, 4
.char:
    mov dil, [rax]
    test dil, dil
    jz .done
    push rax
    call dis_c
    pop rax
    inc rax
    dec ecx
    jnz .char
.done:
    ret

; name: dis_fetch
; in:   esi = bytes (1, 2, 4 or 8)
; out:  rax = the next immediate, sign-extended; dis_pc moved past it
; clobbers: rax, rcx
dis_fetch:
    mov rcx, [rel dis_pc]
    add [rel dis_pc], rsi
    cmp esi, 1
    je .byte
    cmp esi, 2
    je .word
    cmp esi, 4
    je .dword
    mov rax, [rcx]
    ret
.byte:
    movsx rax, byte [rcx]
    ret
.word:
    movsx rax, word [rcx]
    ret
.dword:
    movsxd rax, dword [rcx]
    ret

; name: dis_modrm
; in:   dis_pc at a ModRM byte
; out:  dis_modrm read; eax = its reg field with REX.R
; clobbers: rax, rcx
dis_modrm:
    mov rcx, [rel dis_pc]
    movzx eax, byte [rcx]
    inc qword [rel dis_pc]
    mov [rel dis_modrm_byte], al
    shr eax, 3
    and eax, 7
    test byte [rel dis_rex], REX_R
    jz .done
    or eax, 8
.done:
    ret

; name: dis_rm
; in:   esi = operand size, edx = 1 to name the size of a memory operand,
;       dis_imm_len = immediate bytes after the ModRM operand (for RIP-relative)
; out:  the ModRM register or memory operand appended
; clobbers: caller-saved
dis_rm:
    push rbx
    push r12
    push r13
    movzx ebx, byte [rel dis_modrm_byte]
    mov r12d, ebx
    and r12d, 7                     ; rm
    shr ebx, 6                      ; mod
    cmp ebx, 3
    jne .memory
    mov edi, r12d
    test byte [rel dis_rex], REX_B
    jz .register
    or edi, 8
.register:
    call dis_reg
    jmp .done
.memory:
    test edx, edx
    jz .open
    lea rdi, [rel dis_size_names]
    bsf ecx, esi                    ; 0 byte, 1 word, 2 dword, 3 qword
    lea rdi, [rdi + rcx * 8]
    call dis_s
.open:
    mov dil, '['
    call dis_c
    cmp r12d, 4
    je .sib
    cmp r12d, 5
    jne .base
    test ebx, ebx
    jnz .base
    mov esi, 4                      ; [rel target]: disp32 from the next instruction
    call dis_fetch
    add rax, [rel dis_pc]
    movzx ecx, byte [rel dis_imm_len]
    add rax, rcx
    mov r13, rax
    lea rdi, [rel dis_rel]
    call dis_s
    mov rdi, r13
    call dis_hex
    jmp .close
.base:
    mov edi, r12d
    test byte [rel dis_rex], REX_B
    jz .base_reg
    or edi, 8
.base_reg:
    mov esi, 8
    call dis_reg
    jmp .disp
.sib:
    mov rcx, [rel dis_pc]
    movzx r13d, byte [rcx]
    inc qword [rel dis_pc]
    mov eax, r13d
    and eax, 7
    cmp eax, 5
    jne .sib_base
    test ebx, ebx
    jnz .sib_base
    mov ebx, 2                      ; no base: a disp32 follows
    jmp .sib_index
.sib_base:
    mov edi, eax
    test byte [rel dis_rex], REX_B
    jz .sib_base_reg
    or edi, 8
.sib_base_reg:
    mov esi, 8
    call dis_reg
    mov dil, '+'
    call dis_c
.sib_index:
    mov edi, r13d
    shr edi, 3
    and edi, 7
    test byte [rel dis_rex], REX_X
    jz .index_reg
    or edi, 8
.index_reg:
    cmp edi, 4                      ; rsp as index means none
    je .no_index
    mov esi, 8
    call dis_reg
    shr r13d, 6
    jz .disp
    mov dil, '*'
    call dis_c
    mov ecx, r13d
    mov edi, 1
    shl edi, cl
    add dil, '0'
    call dis_c
    jmp .disp
.no_index:
    mov rax, [rel dis_out]          ; drop the '+' after the base
    cmp byte [rax - 1], '+'
    jne .disp
    dec qword [rel dis_out]
.disp:
    cmp ebx, 1
    jb .close
    mov esi, 1
    je .fetch_disp
    mov esi, 4
.fetch_disp:
    call dis_fetch
    mov rdi, rax
    mov rcx, [rel dis_out]
    xor esi, esi
    cmp byte [rcx - 1], '['         ; no base or index: the bare address
    je .print_disp
    test rax, rax
    jz .close
    inc esi
.print_disp:
    call dis_signed
.close:
    mov dil, ']'
    call dis_c
.done:
    pop r13
    pop r12
    pop rbx
    ret

dis_reg64 db "rax",0,"rcx",0,"rdx",0,"rbx",0,"rsp",0,"rbp",0,"rsi",0,"rdi",0
          db "r8",0,0,"r9",0,0,"r10",0,"r11",0,"r12",0,"r13",0,"r14",0,"r15",0
dis_reg32 db "eax",0,"ecx",0,"edx",0,"ebx",0,"esp",0,"ebp",0,"esi",0,"edi",0
          db "r8d",0,"r9d",0,"r10d","r11d","r12d","r13d","r14d","r15d"
dis_reg16 db "ax",0,0,"cx",0,0,"dx",0,0,"bx",0,0,"sp",0,0,"bp",0,0,"si",0,0,"di",0,0
          db "r8w",0,"r9w",0,"r10w","r11w","r12w","r13w","r14w","r15w"
dis_reg8  db "al",0,0,"cl",0,0,"dl",0,0,"bl",0,0,"spl",0,"bpl",0,"sil",0,"dil",0
          db "r8b",0,"r9b",0,"r10b","r11b","r12b","r13b","r14b","r15b"
dis_reg8_high db "ah",0,0,"ch",0,0,"dh",0,0,"bh",0,0
dis_size_names db "byte ",0,0,0,"word ",0,0,0,"dword ",0,0,"qword ",0,0
dis_rel   db "rel ", 0

section .bss
alignb 8
dis_out        resq 1               ; next output byte
dis_pc         resq 1               ; next instruction byte
dis_start      resq 1               ; first byte of the instruction
dis_rex        resb 1
dis_opsize     resb 1               ; 0x66 seen
dis_rep        resb 1               ; 0xf3 or 0xf2 seen
dis_modrm_byte resb 1
dis_imm_len    resb 1
section .text
