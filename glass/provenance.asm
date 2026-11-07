; Pixel provenance: beside the framebuffer, a map holds for every pixel the id
; of the call chain that last drew it. The framebuffer primitives record each
; draw (prov_rect) and move the map with the pixels on a scroll (prov_scroll).
;
; A chain is the drawing task and up to PROV_DEPTH return addresses: the
; primitive's own return slot, then the frames glass/provwalk.asm finds above
; it. Equal chains share one id; when the table is full new chains get 0.

PROV_DEPTH  equ 6
PROV_CHAINS equ 4096                ; a power of two
PROV_TASK   equ 0                   ; chain record: task id (dword)
PROV_COUNT  equ 4                   ; frames (dword)
PROV_FRAMES equ 8                   ; return addresses (qwords)
PROV_RECORD equ 64

; name: prov_init
; in:   the framebuffer and the page allocator set up
; out:  the map and the chain table allocated and cleared; without a
;       framebuffer or the pages, provenance stays off
; clobbers: caller-saved
prov_init:
    cmp qword [rel fb_base], 0
    je .ret
    mov rdi, [rel fb_width]
    imul rdi, [rel fb_height]
    shl rdi, 2
    add rdi, 4095
    shr rdi, 12
    push rdi
    call page_alloc
    pop rcx
    jc .ret
    push rax
    mov rdi, rax
    shl rcx, 9
    xor eax, eax
    rep stosq
    mov edi, PROV_CHAINS * PROV_RECORD / 4096
    call page_alloc
    pop rdx
    jc .ret
    mov rdi, rax
    mov ecx, PROV_CHAINS * PROV_RECORD / 8
    mov rsi, rax
    xor eax, eax
    rep stosq
    mov [rel prov_chains], rsi
    mov [rel prov_map], rdx         ; last: a set map means both are ready
.ret:
    ret

; name: prov_rect
; in:   rdi = x, rsi = y, rdx = width, rcx = height, rax = the stack slot
;       holding the drawing primitive's return address; interrupts off
; out:  the rectangle's map entries set to the id of the drawing chain
; clobbers: none
prov_rect:
    cmp qword [rel prov_map], 0
    je .ret
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov rbx, rax
    mov r9, rdi
    mov r10, rsi
    mov r11, rdx
    mov r8, rcx
    call prov_chain
    mov rdx, [rel fb_width]
.row:
    test r8, r8
    jz .done
    mov rdi, r10
    imul rdi, rdx
    add rdi, r9
    shl rdi, 2
    add rdi, [rel prov_map]
    mov rcx, r11
    rep stosd
    inc r10
    dec r8
    jmp .row
.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
.ret:
    ret

; name: prov_scroll
; in:   rdi = x, rsi = y, rdx = width, rcx = height, r8 = lines to move up,
;       as for fb_scroll_rect
; out:  the rectangle's map entries moved up the same way
; clobbers: none
prov_scroll:
    cmp qword [rel prov_map], 0
    je .ret
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r9
    push r10
    push r11
    mov r9, rdx
    mov r10, rcx
    sub r10, r8
    mov rax, [rel fb_width]
    shl rax, 2                      ; map pitch
    imul rsi, rax
    lea rdi, [rsi + rdi * 4]
    add rdi, [rel prov_map]
    mov r11, r8
    imul r11, rax
    add r11, rdi
.row:
    test r10, r10
    jz .done
    push rdi
    mov rsi, r11
    mov rcx, r9
    rep movsd
    pop rdi
    add rdi, rax
    add r11, rax
    dec r10
    jmp .row
.done:
    pop r11
    pop r10
    pop r9
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
.ret:
    ret

; name: prov_chain
; in:   rbx = the stack slot holding the drawing primitive's return address
; out:  eax = id of the chain drawing from there, 0 if the table is full
; clobbers: rax, rcx, rdx, rsi, rdi
prov_chain:
    lea rdi, [rel prov_tmp]
    xor eax, eax
    mov ecx, PROV_RECORD / 8
    rep stosq
    mov eax, [rel sched_current]
    mov [rel prov_tmp + PROV_TASK], eax
    mov rdi, [rbx]
    mov [rel prov_tmp + PROV_FRAMES], rdi
    mov dword [rel prov_tmp + PROV_COUNT], 1
    call prov_walk
    jmp prov_intern

; name: prov_intern
; in:   prov_tmp = a chain record
; out:  eax = the id of an equal record in the table, which it is added to
;       if missing; 0 if the table is full
; clobbers: rax, rcx, rdx, rsi, rdi
prov_intern:
    xor eax, eax
    lea rsi, [rel prov_tmp]
    mov ecx, PROV_RECORD / 8
.hash:
    imul rax, rax, 31
    add rax, [rsi]
    add rsi, 8
    dec ecx
    jnz .hash
    mov rdx, rax
    shr rdx, 17
    xor rax, rdx
    and eax, PROV_CHAINS - 1
    mov edx, PROV_CHAINS            ; slots left to probe
.probe:
    mov rdi, rax
    shl rdi, 6
    add rdi, [rel prov_chains]
    cmp dword [rdi + PROV_COUNT], 0
    je .add
    push rdi
    lea rsi, [rel prov_tmp]
    mov ecx, PROV_RECORD / 8
    repe cmpsq
    pop rdi
    je .found
    inc eax
    and eax, PROV_CHAINS - 1
    dec edx
    jnz .probe
    xor eax, eax
    ret
.add:
    push rax
    lea rsi, [rel prov_tmp]
    mov ecx, PROV_RECORD / 8
    rep movsq
    pop rax
.found:
    inc eax
    ret

section .bss
alignb 8
prov_map    resq 1
prov_chains resq 1
prov_tmp    resb PROV_RECORD
section .text
