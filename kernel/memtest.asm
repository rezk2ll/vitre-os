; Memory self-test (test=mem): page allocator and heap stress.

MEMTEST_RUNS  equ 256               ; page runs held at once
MEMTEST_SLOTS equ 64                ; heap blocks held at once
MEMTEST_OPS   equ 4000

; name: selftest_mem
; in:   none
; out:  "[mem] pages ok" and "[mem] heap ok", or a "[mem] FAIL" line
; clobbers: caller-saved
selftest_mem:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rax, 0x2545f4914f6cdd1d
    mov [rel memtest_seed], rax
    mov r15, [rel pmm_free_pages]

    ; allocate runs of 1-8 pages, stamp every page with its own address
    xor r12d, r12d
.page_alloc:
    call memtest_rand
    and eax, 7
    lea rdi, [rax + 1]
    mov r13, rdi
    call page_alloc
    jc .fail_oom
    lea rcx, [rel memtest_runs]
    shl r12, 4
    mov [rcx + r12], rax
    mov [rcx + r12 + 8], r13
    shr r12, 4
    mov rdi, rax                    ; must not touch the kernel or low memory
    cmp rdi, bss_end
    jb .fail_range
    mov rcx, r13
.stamp:
    mov [rdi], rdi
    mov [rdi + PAGE_SIZE - 8], rdi
    add rdi, PAGE_SIZE
    dec rcx
    jnz .stamp
    inc r12d
    cmp r12d, MEMTEST_RUNS
    jb .page_alloc

    ; every stamp must survive: two runs sharing a page would overwrite it
    xor r12d, r12d
.page_check:
    lea rcx, [rel memtest_runs]
    shl r12, 4
    mov rdi, [rcx + r12]
    mov r13, [rcx + r12 + 8]
    shr r12, 4
.check_page:
    cmp [rdi], rdi
    jne .fail_overlap
    cmp [rdi + PAGE_SIZE - 8], rdi
    jne .fail_overlap
    add rdi, PAGE_SIZE
    dec r13
    jnz .check_page
    inc r12d
    cmp r12d, MEMTEST_RUNS
    jb .page_check

    xor r12d, r12d
.page_free:
    lea rcx, [rel memtest_runs]
    shl r12, 4
    mov rdi, [rcx + r12]
    mov rsi, [rcx + r12 + 8]
    shr r12, 4
    call page_free
    inc r12d
    cmp r12d, MEMTEST_RUNS
    jb .page_free
    cmp [rel pmm_free_pages], r15
    jne .fail_leak
    lea rdi, [rel memtest_msg_pages]
    call kputs

    ; heap: random alloc/free; each block is filled with its tag and checked before free
    xor r14d, r14d                  ; operation count
.heap_op:
    call memtest_rand
    and eax, MEMTEST_SLOTS - 1
    mov r12d, eax                   ; slot
    lea rbx, [rel memtest_slots]
    shl r12, 4
    add rbx, r12                    ; rbx = slot: ptr, size (low 32) | tag << 32
    mov rdi, [rbx]
    test rdi, rdi
    jz .heap_alloc
    call memtest_verify_slot
    jne .fail_heap
    mov rdi, [rbx]
    call kfree
    mov qword [rbx], 0
    jmp .heap_next
.heap_alloc:
    call memtest_rand
    xor edx, edx
    mov ecx, 3000
    div ecx
    lea r13d, [rdx + 1]             ; size 1-3000
    mov edi, r13d
    call kmalloc
    jc .fail_oom
    test al, 15
    jnz .fail_align
    mov [rbx], rax
    mov ecx, r13d
    mov rdx, r14
    and edx, 0xff
    shl rdx, 32
    or rdx, rcx
    mov [rbx + 8], rdx
    mov rdi, rax
    mov eax, r14d
    rep stosb                       ; fill with the tag (low byte of the op count)
.heap_next:
    inc r14d
    cmp r14d, MEMTEST_OPS
    jb .heap_op

    xor r12d, r12d                  ; free what is left
.heap_drain:
    lea rbx, [rel memtest_slots]
    shl r12, 4
    add rbx, r12
    shr r12, 4
    mov rdi, [rbx]
    test rdi, rdi
    jz .drained
    call memtest_verify_slot
    jne .fail_heap
    mov rdi, [rbx]
    call kfree
    mov qword [rbx], 0
.drained:
    inc r12d
    cmp r12d, MEMTEST_SLOTS
    jb .heap_drain
    mov rax, [rel heap_free_bytes]
    cmp rax, [rel heap_total_bytes]
    jne .fail_leak
    lea rdi, [rel memtest_msg_heap]
    call kputs
    lea rdi, [rel memtest_msg_blocks]
    call kputs
    call heap_free_blocks
    mov rdi, rax
    call kput_dec
    mov edi, 10
    call kputc
    jmp .done

.fail_oom:
    lea rdi, [rel memtest_msg_oom]
    jmp .fail
.fail_range:
    lea rdi, [rel memtest_msg_range]
    jmp .fail
.fail_overlap:
    lea rdi, [rel memtest_msg_overlap]
    jmp .fail
.fail_leak:
    lea rdi, [rel memtest_msg_leak]
    jmp .fail
.fail_align:
    lea rdi, [rel memtest_msg_align]
    jmp .fail
.fail_heap:
    lea rdi, [rel memtest_msg_corrupt]
.fail:
    call kputs
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: memtest_verify_slot
; in:   rbx = slot
; out:  ZF=1 if every byte of the block still holds the slot's tag
; clobbers: rax, rcx, rdi
memtest_verify_slot:
    mov rdi, [rbx]
    mov ecx, [rbx + 8]
    movzx eax, byte [rbx + 12]
    repe scasb
    ret

; name: memtest_rand
; in:   none
; out:  eax = next pseudo-random value (64-bit LCG, high bits)
; clobbers: rdx
memtest_rand:
    mov rax, [rel memtest_seed]
    mov rdx, 6364136223846793005
    imul rax, rdx
    mov rdx, 1442695040888963407
    add rax, rdx
    mov [rel memtest_seed], rax
    shr rax, 33
    ret

memtest_msg_pages   db "[mem] pages ok", 10, 0
memtest_msg_heap    db "[mem] heap ok", 10, 0
memtest_msg_blocks  db "[mem] free blocks after drain: ", 0
memtest_msg_oom     db "[mem] FAIL out of memory", 10, 0
memtest_msg_range   db "[mem] FAIL page inside the kernel or low memory", 10, 0
memtest_msg_overlap db "[mem] FAIL overlapping pages", 10, 0
memtest_msg_leak    db "[mem] FAIL free count not restored", 10, 0
memtest_msg_align   db "[mem] FAIL unaligned block", 10, 0
memtest_msg_corrupt db "[mem] FAIL heap block overwritten", 10, 0

section .bss
alignb 8
memtest_seed  resq 1
memtest_runs  resq MEMTEST_RUNS * 2
memtest_slots resq MEMTEST_SLOTS * 2
section .text
