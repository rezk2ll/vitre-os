; CPU exception reporting: a full register dump on the log, then halt.

; name: exception_fatal
; in:   rdi = interrupt frame of a CPU exception
; out:  does not return
; clobbers: everything
exception_fatal:
    mov rbx, rdi
    and rsp, -16
    lea rdi, [rel exc_msg_head]
    call kputs
    mov rax, [rbx + INT_FRAME_VECTOR]
    lea rdi, [rel exc_names]
    lea rdi, [rdi + rax * 4]        ; 4-byte name slots, e.g. "UD",0,0
    call kputs
    lea rdi, [rel exc_msg_vec]
    call kputs
    ; written out here, not with kput_dec: a faulting patch of kput_dec must
    ; not fault again inside this dump
    mov eax, [rbx + INT_FRAME_VECTOR]
    mov ecx, 10
    xor edx, edx
    div ecx
    push rdx
    sub rsp, 8
    test eax, eax
    jz .units
    lea edi, [rax + '0']
    call kputc
.units:
    add rsp, 8
    pop rdi
    add edi, '0'
    call kputc
    lea rdi, [rel exc_msg_err]
    call kputs
    mov rdi, [rbx + INT_FRAME_ERROR]
    call kput_hex
    mov edi, 10
    call kputc

    xor r12d, r12d
.reg:
    lea rdi, [rel exc_reg_names]
    lea rdi, [rdi + r12 * 8]
    call kputs
    lea rax, [rel exc_reg_offsets]
    movzx eax, byte [rax + r12]
    mov rdi, [rbx + rax]
    call kput_hex
    inc r12
    mov eax, r12d
    and eax, 3
    mov edi, ' '
    mov esi, 10
    cmovz edi, esi                  ; four registers per line
    call kputc
    cmp r12, EXC_REG_COUNT
    jb .reg

    lea rdi, [rel exc_msg_cr2]
    call kputs
    mov rdi, cr2
    call kput_hex
    lea rdi, [rel exc_msg_cr3]
    call kputs
    mov rdi, cr3
    call kput_hex
    mov edi, 10
    call kputc
    lea rdi, [rel exc_msg_halt]
    call kputs
.halt:
    cli
    hlt
    jmp .halt

exc_msg_head db "[exc] #", 0
exc_msg_vec  db " vector=", 0
exc_msg_err  db " error=", 0
exc_msg_cr2  db "CR2=", 0
exc_msg_cr3  db " CR3=", 0
exc_msg_halt db "[exc] halted", 10, 0

exc_names:
    db "DE",0,0, "DB",0,0, "NMI",0, "BP",0,0, "OF",0,0, "BR",0,0, "UD",0,0, "NM",0,0
    db "DF",0,0, "CSO",0, "TS",0,0, "NP",0,0, "SS",0,0, "GP",0,0, "PF",0,0, "15",0,0
    db "MF",0,0, "AC",0,0, "MC",0,0, "XM",0,0, "VE",0,0, "CP",0,0, "22",0,0, "23",0,0
    db "24",0,0, "25",0,0, "26",0,0, "27",0,0, "HV",0,0, "VC",0,0, "SX",0,0, "31",0,0

; "NAME=" padded to 8 bytes, in dump order
exc_reg_names:
    db "RAX=",0,0,0,0, "RBX=",0,0,0,0, "RCX=",0,0,0,0, "RDX=",0,0,0,0
    db "RSI=",0,0,0,0, "RDI=",0,0,0,0, "RBP=",0,0,0,0, "RSP=",0,0,0,0
    db "R8=",0,0,0,0,0, "R9=",0,0,0,0,0, "R10=",0,0,0,0, "R11=",0,0,0,0
    db "R12=",0,0,0,0, "R13=",0,0,0,0, "R14=",0,0,0,0, "R15=",0,0,0,0
    db "RIP=",0,0,0,0, "CS=",0,0,0,0,0, "RFL=",0,0,0,0, "SS=",0,0,0,0,0
exc_reg_offsets:
    db INT_FRAME_RAX, INT_FRAME_RBX, INT_FRAME_RCX, INT_FRAME_RDX
    db INT_FRAME_RSI, INT_FRAME_RDI, INT_FRAME_RBP, INT_FRAME_RSP
    db INT_FRAME_R8, INT_FRAME_R9, INT_FRAME_R10, INT_FRAME_R11
    db INT_FRAME_R12, INT_FRAME_R13, INT_FRAME_R14, INT_FRAME_R15
    db INT_FRAME_RIP, INT_FRAME_CS, INT_FRAME_RFLAGS, INT_FRAME_SS
EXC_REG_COUNT equ 20
