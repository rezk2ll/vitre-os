; Inspect mode: F12 in any app freezes the screen under a bar; Esc or F12 puts
; the screen and the provenance map back as they were. It runs inside the
; kbd_poll call of the app that read the F12.

INSP_BG      equ 0x002e3440
INSP_EDGE    equ 0x0088c0d0
INSP_BAR_H   equ 16

; name: insp_hotkey
; in:   F12 read by kbd_poll, interrupts on
; out:  inspect mode ran and eax = 0, ZF=1; or, when it cannot run or is
;       already running, eax = KEY_F12, ZF=0
; clobbers: rcx, rdx
insp_hotkey:
    cmp byte [rel insp_active], 0
    jne .key
    cmp qword [rel prov_map], 0
    je .key
    cmp byte [rel console_ready], 0
    je .key
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    sub rsp, 8
    call insp_run
    add rsp, 8
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    xor eax, eax
    ret
.key:
    mov eax, KEY_F12
    test eax, eax
    ret

; name: insp_run
; in:   none
; out:  inspect mode ran until Esc or F12; the screen and the map restored
; clobbers: caller-saved
insp_run:
    sub rsp, 8
    mov byte [rel insp_active], 1
    call insp_alloc
    jc .done
    call insp_copy_out
    call insp_bar
    call mouse_click                ; forget earlier clicks
.loop:
    call kbd_poll
    jz .mouse
    cmp eax, KEY_ESC
    je .leave
    cmp eax, KEY_F12
    je .leave
    jmp .loop
.mouse:
    call mouse_click
    jc .idle
    jmp .loop
.idle:
    hlt
    jmp .loop
.leave:
    call insp_copy_in
    call mouse_click
.done:
    mov byte [rel insp_active], 0
    add rsp, 8
    ret

; name: insp_alloc
; in:   none
; out:  insp_screen and insp_map hold room for a copy of the screen and of
;       the map, allocated on first use; CF=1 if the pages are missing
; clobbers: caller-saved
insp_alloc:
    cmp qword [rel insp_map], 0
    jne .ok
    mov rdi, [rel fb_width]
    imul rdi, [rel fb_height]
    shl rdi, 3                      ; both copies, 4 bytes a pixel each
    add rdi, 4095
    shr rdi, 12
    call page_alloc
    jc .ret
    mov [rel insp_screen], rax
    mov rcx, [rel fb_width]
    imul rcx, [rel fb_height]
    lea rax, [rax + rcx * 4]
    mov [rel insp_map], rax
.ok:
    clc
.ret:
    ret

; name: insp_copy_out
; in:   none
; out:  the screen and the map copied to insp_screen and insp_map
; clobbers: caller-saved
insp_copy_out:
    xor eax, eax
    jmp insp_copy

; name: insp_copy_in
; in:   none
; out:  the screen and the map put back from insp_screen and insp_map
; clobbers: caller-saved
insp_copy_in:
    mov eax, 1

; name: insp_copy
; in:   eax = 0 to save, 1 to restore
; out:  the screen and the map copied that way
; clobbers: caller-saved
insp_copy:
    push rbx
    push r12
    push r13
    pushfq
    cli
    call cursor_off
    mov ebx, eax
    mov rcx, [rel fb_width]
    imul rcx, [rel fb_height]
    mov rsi, [rel prov_map]
    mov rdi, [rel insp_map]
    test ebx, ebx
    jz .map
    xchg rsi, rdi
.map:
    rep movsd
    mov r12, [rel insp_screen]
    mov r13, [rel fb_base]
    xor edx, edx
.row:
    cmp rdx, [rel fb_height]
    jae .done
    mov rsi, r13
    mov rdi, r12
    test ebx, ebx
    jz .copy
    xchg rsi, rdi
.copy:
    mov rcx, [rel fb_width]
    rep movsd
    mov rax, [rel fb_width]
    lea r12, [r12 + rax * 4]
    add r13, [rel fb_pitch]
    inc rdx
    jmp .row
.done:
    call cursor_on
    popfq
    pop r13
    pop r12
    pop rbx
    ret

; name: insp_bar
; in:   none
; out:  the inspect bar drawn across the top of the screen
; clobbers: caller-saved
insp_bar:
    sub rsp, 8
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov ecx, INSP_BAR_H
    mov r8d, INSP_BG
    call fb_fill_rect
    xor edi, edi
    xor esi, esi
    lea rdx, [rel insp_msg_bar]
    mov ecx, INSP_EDGE
    mov r8d, INSP_BG
    call dt_text
    add rsp, 8
    ret

insp_msg_bar     db "Inspect: click any pixel to see the code that drew it. Esc leaves.", 0

section .bss
alignb 8
insp_screen resq 1
insp_map    resq 1
insp_active resb 1
section .text
