; Forge self-check: every module in the source area must assemble to the
; bytes NASM put in the kernel image.

FORGE_CHECK_PAGES equ 16

; name: forge_check
; in:   rdi = arguments (ignored)
; out:  one "[forge] path: ..." line per module
; clobbers: caller-saved
forge_check:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, [rel src_area]
    test rbx, rbx
    jz .no_source
    mov edi, FORGE_CHECK_PAGES
    call page_alloc
    jc .no_memory
    mov r15, rax
    mov r12d, [rbx + SRC_HDR_COUNT]
    lea r13, [rbx + SRC_DIR]
.module:
    test r12d, r12d
    jz .done
    lea rdi, [rel forge_msg_prefix]
    call kputs
    mov rdi, r13
    call kputs
    lea rdi, [rel forge_msg_colon]
    call kputs
    mov edi, [r13 + SRC_DIR_START]
    add rdi, rbx
    mov esi, [r13 + SRC_DIR_LEN]
    call forge_module_origin
    jc .no_origin
    mov r14, rax
    mov edi, [r13 + SRC_DIR_START]
    add rdi, rbx
    mov esi, [r13 + SRC_DIR_LEN]
    mov rdx, r14
    mov rcx, r15
    mov r8d, FORGE_CHECK_PAGES * PAGE_SIZE
    call forge_assemble
    jc .error
    mov rdi, r15
    mov rsi, r14
    mov rdx, rax
    call forge_compare
.next:
    add r13, SRC_DIR_ENTRY
    dec r12d
    jmp .module
.no_origin:
    lea rdi, [rel forge_msg_no_origin]
    call kputs
    jmp .next
.error:
    call forge_log_error
    jmp .next
.done:
    mov rdi, r15
    mov esi, FORGE_CHECK_PAGES
    call page_free
    jmp .return
.no_source:
    lea rdi, [rel forge_msg_no_source]
    call kputs
    jmp .return
.no_memory:
    lea rdi, [rel forge_msg_no_memory]
    call kputs
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_log_error
; in:   forge_assemble just failed
; out:  "line N: message" on the log
; clobbers: caller-saved
forge_log_error:
    sub rsp, 8
    lea rdi, [rel forge_msg_line]
    call kputs
    mov rdi, [rel forge_error_line]
    call [rel jt_kput_dec]
    lea rdi, [rel forge_msg_colon]
    call kputs
    mov rdi, [rel forge_error]
    call kputs
    mov edi, 10
    call kputc
    add rsp, 8
    ret

; name: forge_compare
; in:   rdi = Forge output, rsi = kernel address, rdx = length
; out:  "N bytes, same as the kernel" or the first difference on the log
; clobbers: caller-saved
forge_compare:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    xor ecx, ecx
.byte:
    cmp rcx, rbx
    jae .same
    mov al, [r12 + rcx]
    cmp al, [r13 + rcx]
    jne .differs
    inc rcx
    jmp .byte
.same:
    mov rdi, rbx
    call [rel jt_kput_dec]
    lea rdi, [rel forge_msg_same]
    call kputs
    jmp .done
.differs:
    mov rbx, rcx
    lea rdi, [rel forge_msg_differs]
    call kputs
    mov rdi, rbx
    call [rel jt_kput_dec]
    lea rdi, [rel forge_msg_forge]
    call kputs
    movzx edi, byte [r12 + rbx]
    call kput_hex
    lea rdi, [rel forge_msg_nasm]
    call kputs
    movzx edi, byte [r13 + rbx]
    call kput_hex
    mov edi, 10
    call kputc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: forge_module_origin
; in:   rdi = module source, rsi = its length
; out:  rax = kernel address of the first "name:" line in it, CF=1 if none
; clobbers: caller-saved
forge_module_origin:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    lea r12, [rdi + rsi]
.line:
    lea rdi, [rel forge_word]
    xor ecx, ecx
.char:
    lea rax, [rbx + rcx]
    cmp rax, r12
    jae .missing
    movzx eax, byte [rax]
    cmp eax, ':'
    je .name
    cmp eax, ' '
    jbe .skip
    cmp eax, ';'
    je .skip
    cmp ecx, FORGE_NAME_MAX
    jae .skip
    mov [rdi + rcx], al
    inc ecx
    jmp .char
.skip:
    cmp rbx, r12
    jae .missing
    inc rbx
    cmp byte [rbx - 1], 10
    jne .skip
    jmp .line
.name:
    test ecx, ecx
    jz .skip
    mov byte [rdi + rcx], 0
    call lab_lookup
    add rsp, 8
    pop r12
    pop rbx
    ret
.missing:
    add rsp, 8
    pop r12
    pop rbx
    stc
    ret

forge_msg_prefix    db "[forge] ", 0
forge_msg_colon     db ": ", 0
forge_msg_line      db "line ", 0
forge_msg_same      db " bytes, same as the kernel", 10, 0
forge_msg_differs   db "differs at byte ", 0
forge_msg_forge     db ": forge ", 0
forge_msg_nasm      db ", kernel ", 0
forge_msg_no_origin db "no label to place it", 10, 0
forge_msg_no_source db "[forge] no source area", 10, 0
forge_msg_no_memory db "[forge] out of memory", 10, 0
