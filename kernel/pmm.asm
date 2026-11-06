; Physical page allocator: one bit per 4 KiB page below 4 GiB (the
; identity-mapped range), set = used. Built from the E820 map.

PAGE_SIZE    equ 4096
PMM_MAX_PAGES equ 0x100000          ; 4 GiB / 4 KiB
PMM_LOW_RESERVED equ 0x100000       ; BIOS data, boot structures, kernel stack

; name: pmm_init
; in:   E820 map in boot info, kernel image and .bss below bss_end
; out:  usable RAM above 1 MiB and past the kernel marked free
; clobbers: caller-saved
pmm_init:
    push rbx
    push r12
    push r13
    lea rdi, [rel pmm_bitmap]       ; everything used until E820 says otherwise
    mov ecx, PMM_MAX_PAGES / 8
    mov al, 0xff
    rep stosb
    mov qword [rel pmm_free_pages], 0
    mov qword [rel pmm_total_pages], 0

    movzx r12d, word [BOOTINFO_E820_COUNT]
    mov rbx, BOOTINFO_E820
.region:
    test r12d, r12d
    jz .regions_done
    cmp dword [rbx + 16], 1         ; type 1 = usable RAM
    jne .next_region
    mov rdi, [rbx]                  ; round start up, end down to pages
    add rdi, PAGE_SIZE - 1
    and rdi, -PAGE_SIZE
    mov rsi, [rbx]
    add rsi, [rbx + 8]
    and rsi, -PAGE_SIZE
    mov rax, PMM_MAX_PAGES * PAGE_SIZE
    cmp rsi, rax
    cmova rsi, rax
    cmp rdi, rsi
    jae .next_region
    mov r13, rsi
    sub r13, rdi
    shr r13, 12
    add [rel pmm_total_pages], r13
    call pmm_mark_free
.next_region:
    add rbx, 24
    dec r12d
    jmp .region
.regions_done:
    xor edi, edi                    ; low memory and the kernel stay used
    mov rsi, bss_end + PAGE_SIZE - 1
    and rsi, -PAGE_SIZE
    call pmm_mark_used
    pop r13
    pop r12
    pop rbx
    ret

; name: pmm_mark_free
; in:   rdi = start, rsi = end (page aligned)
; out:  pages in [start, end) free
; clobbers: rax, rdi, rcx
pmm_mark_free:
    lea rcx, [rel pmm_bitmap]
.next:
    cmp rdi, rsi
    jae .done
    mov rax, rdi
    shr rax, 12
    btr [rcx], rax
    jnc .already
    inc qword [rel pmm_free_pages]
.already:
    add rdi, PAGE_SIZE
    jmp .next
.done:
    ret

; name: pmm_mark_used
; in:   rdi = start, rsi = end (page aligned)
; out:  pages in [start, end) used
; clobbers: rax, rdi, rcx
pmm_mark_used:
    lea rcx, [rel pmm_bitmap]
.next:
    cmp rdi, rsi
    jae .done
    mov rax, rdi
    shr rax, 12
    bts [rcx], rax
    jc .already
    dec qword [rel pmm_free_pages]
.already:
    add rdi, PAGE_SIZE
    jmp .next
.done:
    ret

; name: page_alloc
; in:   rdi = number of contiguous pages (>= 1)
; out:  rax = physical address of the first page, CF=1 if none
; clobbers: rcx, rdx, rsi, rdi, r8
page_alloc:
    lea r8, [rel pmm_bitmap]
    mov rsi, [rel pmm_hint]
    xor ecx, ecx                    ; length of the current free run
    xor edx, edx                    ; pages scanned
.scan:
    cmp rdx, PMM_MAX_PAGES
    jae .none
    cmp rsi, PMM_MAX_PAGES
    jb .in_range
    xor esi, esi                    ; wrap; a run cannot span the wrap
    xor ecx, ecx
.in_range:
    bt [r8], rsi
    jc .used
    inc rcx
    cmp rcx, rdi
    je .found
    jmp .step
.used:
    xor ecx, ecx
.step:
    inc rsi
    inc rdx
    jmp .scan
.found:
    sub rsi, rdi
    inc rsi                         ; first page of the run
    mov rax, rsi
.mark:
    bts [r8], rsi
    inc rsi
    dec rcx
    jnz .mark
    mov [rel pmm_hint], rsi
    sub [rel pmm_free_pages], rdi
    shl rax, 12
    clc
    ret
.none:
    mov eax, 1
    stc
    ret

; name: page_free
; in:   rdi = physical address of the first page, rsi = number of pages
; out:  pages returned to the pool
; clobbers: rax, rcx, rdi, rsi
page_free:
    lea rcx, [rel pmm_bitmap]
    shr rdi, 12
.next:
    test rsi, rsi
    jz .done
    btr [rcx], rdi
    jnc .not_used
    inc qword [rel pmm_free_pages]
.not_used:
    inc rdi
    dec rsi
    jmp .next
.done:
    ret

section .bss
alignb 8
pmm_free_pages  resq 1
pmm_total_pages resq 1
pmm_hint        resq 1
pmm_bitmap      resb PMM_MAX_PAGES / 8
section .text
