; Live patching: assemble a module from the source area into a fresh code
; slot, then point its jump table entries at the new code. Only the last
; patch keeps the pointers it replaced, so rollback goes back one patch.
; Code slots are never freed: a task may still be running the old code.

PATCH_SLOT_PAGES equ 4
PATCH_SLOT       equ 0              ; jump table slot
PATCH_OLD        equ 8              ; pointer before the patch
PATCH_NEW        equ 16
PATCH_ENTRY      equ 24

; name: patch_apply
; in:   rdi = module path
; out:  the module's patchable functions run from new code; result on the
;       log; CF=1 if nothing changed
; clobbers: caller-saved
patch_apply:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    lea rdi, [rel patch_msg_prefix]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel forge_msg_colon]
    call kputs
    mov rdi, rbx
    call src_find
    jc .missing
    mov r12, rax
    mov r13, rdx
    mov edi, PATCH_SLOT_PAGES
    call page_alloc
    jc .no_memory
    mov r14, rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r14
    mov r8d, PATCH_SLOT_PAGES * PAGE_SIZE
    call forge_assemble
    jc .error
    mov r15, rax
    mov rdi, r14
    mov rsi, r15
    call patch_collect
    test rax, rax
    jz .nothing
    mov rbx, rax
    mov rdi, rax
    call [rel jt_kput_dec]
    lea rdi, [rel patch_msg_functions]
    call kputs
    lea rdi, [rel patch_msg_comma]
    call kputs
    mov rdi, r15
    call [rel jt_kput_dec]
    lea rdi, [rel patch_msg_bytes_at]
    call kputs
    mov rdi, r14
    call kput_hex
    mov edi, 10
    call kputc
    pushfq
    cli
    mov [rel patch_count], rbx
    mov [rel patch_code], r14
    lea rax, [r14 + r15]
    mov [rel patch_code_end], rax
    mov rax, [rel timer_ticks]
    mov [rel patch_since], rax
    lea r12, [rel patch_entries]
.swap:
    mov rdi, [r12 + PATCH_SLOT]
    mov rsi, [r12 + PATCH_NEW]
    call patch_set_slot
    add r12, PATCH_ENTRY
    dec rbx
    jnz .swap
    popfq
    clc
    jmp .return
.nothing:
    lea rdi, [rel patch_msg_nothing]
    call kputs
    jmp .free
.error:
    call forge_log_error
.free:
    mov rdi, r14
    mov esi, PATCH_SLOT_PAGES
    call page_free
    stc
    jmp .return
.missing:
    lea rdi, [rel patch_msg_missing]
    call kputs
    stc
    jmp .return
.no_memory:
    lea rdi, [rel forge_msg_no_memory]
    call kputs
    stc
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: patch_collect
; in:   rdi = new code, rsi = its size; Forge labels of the module just
;       assembled
; out:  rax = number of patchable functions the module defines, each in
;       patch_entries with its slot, current pointer and new address
; clobbers: caller-saved
patch_collect:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi
    lea r14, [rdi + rsi]
    lea rbx, [rel sym_table]
    mov r12d, SYM_COUNT
    xor r15d, r15d
.record:
    cmp dword [rbx + SYM_SLOT], 0
    jl .next
    lea rdi, [rbx + SYM_NAME]
    call forge_find
    jc .next
    mov rax, [rax + FORGE_LABEL_VAL]
    cmp rax, r13
    jb .next
    cmp rax, r14
    jae .next
    imul rcx, r15, PATCH_ENTRY
    lea rdx, [rel patch_entries]
    add rdx, rcx
    mov [rdx + PATCH_NEW], rax
    movsxd rax, dword [rbx + SYM_SLOT]
    mov [rdx + PATCH_SLOT], rax
    lea rcx, [rel jump_table]
    mov rax, [rcx + rax * 8]
    mov [rdx + PATCH_OLD], rax
    inc r15
.next:
    add rbx, SYM_RECORD
    dec r12d
    jnz .record
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: patch_set_slot
; in:   rdi = jump table slot, rsi = new pointer
; out:  slot and symbol table address updated
; clobbers: rax, rcx, rdx
patch_set_slot:
    lea rax, [rel jump_table]
    mov [rax + rdi * 8], rsi        ; one aligned store: callers see old or new
    lea rax, [rel sym_table]
    mov ecx, SYM_COUNT
.record:
    movsxd rdx, dword [rax + SYM_SLOT]
    cmp rdx, rdi
    jne .next
    mov [rax + SYM_ADDR], rsi
.next:
    add rax, SYM_RECORD
    dec ecx
    jnz .record
    ret

; name: patch_rollback
; in:   none
; out:  rax = number of jump table entries restored, 0 if no patch is live
; clobbers: caller-saved
patch_rollback:
    push rbx
    push r12
    push r13
    pushfq
    cli
    mov r13, [rel patch_count]
    mov rbx, r13
    mov qword [rel patch_count], 0
    mov qword [rel patch_code], 0
    mov qword [rel patch_code_end], 0
    lea r12, [rel patch_entries]
.restore:
    test rbx, rbx
    jz .done
    mov rdi, [r12 + PATCH_SLOT]
    mov rsi, [r12 + PATCH_OLD]
    call patch_set_slot
    add r12, PATCH_ENTRY
    dec rbx
    jmp .restore
.done:
    popfq
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

; name: cmd_patch
; in:   rdi = module path
; out:  module patched live, or the reason on the log
; clobbers: caller-saved
cmd_patch:
    cmp byte [rdi], 0
    jne patch_apply
    lea rdi, [rel patch_msg_usage]
    jmp kputs

; name: cmd_rollback
; in:   rdi = arguments (ignored)
; out:  the last patch undone
; clobbers: caller-saved
cmd_rollback:
    sub rsp, 8
    call patch_rollback
    test rax, rax
    jz .none
    push rax
    sub rsp, 8
    lea rdi, [rel patch_msg_rolled]
    call kputs
    add rsp, 8
    pop rdi
    call [rel jt_kput_dec]
    lea rdi, [rel patch_msg_functions]
    call kputs
    mov edi, 10
    call kputc
    add rsp, 8
    ret
.none:
    lea rdi, [rel patch_msg_no_patch]
    call kputs
    add rsp, 8
    ret

patch_msg_prefix    db "[patch] ", 0
patch_msg_functions db " functions", 0
patch_msg_comma     db ", ", 0
patch_msg_bytes_at  db " bytes at ", 0
patch_msg_missing   db "not in the source area", 10, 0
patch_msg_nothing   db "no patchable function in it", 10, 0
patch_msg_usage     db "usage: patch <module>", 10, 0
patch_msg_rolled    db "[patch] rolled back ", 0
patch_msg_no_patch  db "[patch] no live patch", 10, 0

section .bss
alignb 8
patch_count    resq 1
patch_code     resq 1               ; new code of the live patch
patch_code_end resq 1
patch_since    resq 1               ; timer_ticks when it went live
patch_entries  resb PATCH_ENTRY * JT_COUNT
section .text
