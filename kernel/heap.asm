; Kernel heap: first-fit over an address-ordered free list, with
; coalescing on free. It grows by taking contiguous pages from the page
; allocator.
;
; Every block starts with a 16-byte header: size of the whole block
; (multiple of 16) and, for free blocks, the next free block. kmalloc
; returns the address just past the header.

HEAP_HDR      equ 16
HEAP_MIN      equ 32                ; smallest block, header included
HEAP_GROW_PAGES equ 256             ; 1 MiB per growth step

; name: kmalloc
; in:   rdi = size in bytes (> 0)
; out:  rax = 16-byte aligned pointer, CF=1 if out of memory
; clobbers: rcx, rdx, rsi, rdi, r8
kmalloc:
    add rdi, HEAP_HDR + 15
    and rdi, -16
    cmp rdi, HEAP_MIN
    jae .sized
    mov edi, HEAP_MIN
.sized:
    lea rsi, [rel heap_free_list]   ; rsi = address of the link to the current block
.walk:
    mov rax, [rsi]
    test rax, rax
    jz .grow
    mov rcx, [rax]                  ; block size
    cmp rcx, rdi
    jae .fit
    lea rsi, [rax + 8]
    jmp .walk
.fit:
    mov rdx, rcx
    sub rdx, rdi
    cmp rdx, HEAP_MIN
    jb .take_whole
    lea r8, [rax + rdi]             ; split: the tail stays free
    mov [r8], rdx
    mov rcx, [rax + 8]
    mov [r8 + 8], rcx
    mov [rsi], r8
    mov [rax], rdi
    jmp .taken
.take_whole:
    mov rcx, [rax + 8]
    mov [rsi], rcx
.taken:
    mov rcx, [rax]
    sub [rel heap_free_bytes], rcx
    mov qword [rax + 8], 0
    add rax, HEAP_HDR
    clc
    ret
.grow:
    push rdi
    add rdi, PAGE_SIZE - 1
    shr rdi, 12
    cmp rdi, HEAP_GROW_PAGES
    jae .pages
    mov edi, HEAP_GROW_PAGES
.pages:
    push rdi
    sub rsp, 8
    call page_alloc
    lea rsp, [rsp + 8]              ; keeps CF from page_alloc
    pop rsi
    pop rdi
    jc .oom
    push rdi
    shl rsi, 12
    add [rel heap_total_bytes], rsi
    add [rel heap_free_bytes], rsi
    mov [rax], rsi
    lea rdi, [rax + HEAP_HDR]
    call heap_insert                ; behaves like freeing the new chunk
    pop rdi
    jmp .sized
.oom:
    mov eax, 1
    stc
    ret

; name: kfree
; in:   rdi = pointer from kmalloc (0 is ignored)
; out:  block returned and merged with free neighbours
; clobbers: rax, rcx, rdx, rsi, rdi
kfree:
    test rdi, rdi
    jz .done
    mov rax, [rdi - HEAP_HDR]
    add [rel heap_free_bytes], rax
    jmp heap_insert
.done:
    ret

; name: heap_insert
; in:   rdi = pointer just past a block header (block size already set)
; out:  block linked into the address-ordered free list, coalesced
; clobbers: rax, rcx, rdx, rsi, rdi
heap_insert:
    sub rdi, HEAP_HDR               ; rdi = block
    lea rsi, [rel heap_free_list]
    xor edx, edx                    ; previous free block (0 = none)
.find:
    mov rax, [rsi]
    test rax, rax
    jz .link
    cmp rax, rdi
    ja .link
    mov rdx, rax
    lea rsi, [rax + 8]
    jmp .find
.link:
    mov [rdi + 8], rax              ; block -> next
    mov [rsi], rdi                  ; prev -> block
    test rax, rax                   ; merge with next if adjacent
    jz .merge_prev
    mov rcx, [rdi]
    add rcx, rdi
    cmp rcx, rax
    jne .merge_prev
    mov rcx, [rax]
    add [rdi], rcx
    mov rcx, [rax + 8]
    mov [rdi + 8], rcx
.merge_prev:
    test rdx, rdx                   ; merge into previous if adjacent
    jz .done
    mov rcx, [rdx]
    add rcx, rdx
    cmp rcx, rdi
    jne .done
    mov rcx, [rdi]
    add [rdx], rcx
    mov rcx, [rdi + 8]
    mov [rdx + 8], rcx
.done:
    ret

; name: heap_free_blocks
; in:   none
; out:  rax = number of blocks on the free list
; clobbers: rcx
heap_free_blocks:
    xor eax, eax
    mov rcx, [rel heap_free_list]
.next:
    test rcx, rcx
    jz .done
    inc rax
    mov rcx, [rcx + 8]
    jmp .next
.done:
    ret

section .bss
alignb 8
heap_free_list   resq 1
heap_free_bytes  resq 1
heap_total_bytes resq 1
section .text
