; The mouse pointer, drawn over the framebuffer from the mouse IRQ. It shows
; from the first movement on. Every framebuffer writer runs with interrupts
; off and the pointer lifted (cursor_off / cursor_on), so the pixels saved
; under it never go stale.

CURSOR_W equ 12
CURSOR_H equ 18

; name: cursor_off
; in:   interrupts off
; out:  the pointer lifted, the pixels under it restored
; clobbers: none
cursor_off:
    cmp byte [rel cursor_up], 0
    je .ret
    push rax
    xor eax, eax
    call cursor_walk
    mov byte [rel cursor_up], 0
    pop rax
.ret:
    ret

; name: cursor_on
; in:   interrupts off
; out:  the pointer drawn at the mouse position, once the mouse has moved
; clobbers: none
cursor_on:
    cmp qword [rel mouse_moves], 0
    je .ret
    cmp byte [rel console_ready], 0
    je .ret
    push rax
    mov eax, [rel mouse_x]
    mov [rel cursor_x], eax
    mov eax, [rel mouse_y]
    mov [rel cursor_y], eax
    mov eax, 1
    call cursor_walk
    mov byte [rel cursor_up], 1
    pop rax
.ret:
    ret

; name: cursor_walk
; in:   eax = 1 to save the pixels and draw, 0 to restore them
; out:  every on-screen pixel of the sprite at cursor_x, cursor_y visited
; clobbers: rax
cursor_walk:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    mov r8d, eax
    lea rsi, [rel cursor_sprite]
    lea rbx, [rel cursor_saved]
    xor edx, edx                    ; row
.row:
    mov eax, [rel cursor_y]
    add eax, edx
    cmp rax, [rel fb_height]
    jae .done
    mov rdi, rax
    imul rdi, [rel fb_pitch]
    add rdi, [rel fb_base]
    xor ecx, ecx                    ; column
.col:
    mov eax, [rel cursor_x]
    add eax, ecx
    cmp rax, [rel fb_width]
    jae .next_row
    lea rax, [rdi + rax * 4]
    test r8d, r8d
    jz .restore
    push rdx
    mov edx, [rax]
    mov [rbx], edx
    pop rdx
    cmp byte [rsi + rcx], 'X'
    je .black
    cmp byte [rsi + rcx], '.'
    jne .skip
    mov dword [rax], 0xffffff
    jmp .skip
.black:
    mov dword [rax], 0x000000
    jmp .skip
.restore:
    push rdx
    mov edx, [rbx]
    mov [rax], edx
    pop rdx
.skip:
    add rbx, 4
    inc ecx
    cmp ecx, CURSOR_W
    jb .col
.next_row:
    lea rbx, [rel cursor_saved]
    lea eax, [edx + 1]
    imul eax, eax, CURSOR_W * 4
    add rbx, rax
    add rsi, CURSOR_W
    inc edx
    cmp edx, CURSOR_H
    jb .row
.done:
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

cursor_sprite:
    db "X           "
    db "XX          "
    db "X.X         "
    db "X..X        "
    db "X...X       "
    db "X....X      "
    db "X.....X     "
    db "X......X    "
    db "X.......X   "
    db "X........X  "
    db "X.........X "
    db "X......XXXXX"
    db "X...X..X    "
    db "X..XX..X    "
    db "X.X  X..X   "
    db "XX   X..X   "
    db "X     X..X  "
    db "      XXXX  "

section .bss
alignb 4
cursor_x     resd 1
cursor_y     resd 1
cursor_saved resd CURSOR_W * CURSOR_H
cursor_up    resb 1
section .text
