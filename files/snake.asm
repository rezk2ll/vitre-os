; snake.asm: the arrows steer, each green square makes the snake longer,
; a wall or the snake's own body ends the game. q or Esc leaves.
; Try: run snake.asm

COLS  equ 32
ROWS  equ 24
CELL  equ 32
CAP   equ 1024                      ; ring of body cells, a power of two
STEP  equ 110                       ; milliseconds per move
BG    equ 0x002e3440
BODY  equ 0x0088c0d0
FOOD  equ 0x00a3be8c

start:
    push rbx
    push r12
    push r13
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov rcx, [rel fb_height]
    mov r8d, BG
    call fb_fill_rect
    mov rax, [rel timer_ticks]
    mov [rel seed], rax
    mov [rel next], rax
    mov byte [rel xs], 16
    mov byte [rel ys], 12
    lea rbx, [rel occ]
    mov byte [rbx + 12 * COLS + 16], 1
    mov edi, 16
    mov esi, 12
    mov edx, BODY
    call cell
    call place_food
.wait:
    call kbd_poll
    jz .idle
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    mov ecx, 3
    cmp eax, KEY_UP
    je .turn
    mov ecx, 1
    cmp eax, KEY_DOWN
    je .turn
    mov ecx, 2
    cmp eax, KEY_LEFT
    je .turn
    xor ecx, ecx
    cmp eax, KEY_RIGHT
    jne .wait
.turn:
    movzx eax, byte [rel dir]
    xor eax, ecx
    cmp eax, 2                      ; straight back into the body
    je .wait
    mov [rel want], cl
    jmp .wait
.idle:
    mov rax, [rel timer_ticks]
    cmp rax, [rel next]
    jae .step
    call task_yield
    jmp .wait
.step:
    add rax, STEP
    mov [rel next], rax
    movzx eax, byte [rel want]
    mov [rel dir], al
    mov r12d, [rel head]
    lea rbx, [rel xs]
    movzx edi, byte [rbx + r12]
    lea rbx, [rel ys]
    movzx esi, byte [rbx + r12]
    test eax, eax
    jnz .not_right
    inc edi
.not_right:
    cmp eax, 1
    jne .not_down
    inc esi
.not_down:
    cmp eax, 2
    jne .not_left
    dec edi
.not_left:
    cmp eax, 3
    jne .moved
    dec esi
.moved:
    cmp edi, COLS                   ; unsigned, so -1 is out too
    jae .over
    cmp esi, ROWS
    jae .over
    inc r12d
    and r12d, CAP - 1
    mov [rel head], r12d
    lea rbx, [rel xs]
    mov [rbx + r12], dil
    lea rbx, [rel ys]
    mov [rbx + r12], sil
    mov r13d, esi
    shl r13d, 5
    add r13d, edi
    cmp r13d, [rel food]
    jne .no_food
    add dword [rel grow], 3
    inc dword [rel score]
.no_food:
    cmp dword [rel grow], 0
    je .cut
    dec dword [rel grow]
    jmp .check
.cut:
    mov ecx, [rel tail]
    lea rbx, [rel xs]
    movzx edi, byte [rbx + rcx]
    lea rbx, [rel ys]
    movzx esi, byte [rbx + rcx]
    inc ecx
    and ecx, CAP - 1
    mov [rel tail], ecx
    mov eax, esi
    shl eax, 5
    add eax, edi
    lea rbx, [rel occ]
    mov byte [rbx + rax], 0
    mov edx, BG
    call cell
.check:
    lea rbx, [rel occ]
    cmp byte [rbx + r13], 0
    jne .over
    mov byte [rbx + r13], 1
    mov edi, r13d
    and edi, COLS - 1
    mov esi, r13d
    shr esi, 5
    mov edx, BODY
    call cell
    cmp r13d, [rel food]
    jne .wait
    call place_food
    jmp .wait
.over:
    mov edi, 800
    call timer_sleep_ms
.quit:
    call shell_clear_screen
    lea rdi, [rel msg_score]
    call kputs
    mov edi, [rel score]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    pop r13
    pop r12
    pop rbx
    ret

; name: cell
; in:   edi = column, esi = row, edx = colour
; out:  the cell drawn
; clobbers: caller-saved
cell:
    mov r8d, edx
    shl edi, 5
    inc edi
    shl esi, 5
    inc esi
    mov edx, CELL - 2
    mov ecx, CELL - 2
    jmp fb_fill_rect

; name: place_food
; in:   none
; out:  food on a random free cell, drawn
; clobbers: caller-saved
place_food:
    sub rsp, 8
.again:
    mov rax, [rel seed]
    mov rcx, 6364136223846793005
    imul rax, rcx
    mov rcx, 1442695040888963407
    add rax, rcx
    mov [rel seed], rax
    shr rax, 33
    xor edx, edx
    mov ecx, COLS * ROWS
    div rcx
    lea rcx, [rel occ]
    cmp byte [rcx + rdx], 0
    jne .again
    mov [rel food], edx
    mov edi, edx
    and edi, COLS - 1
    mov esi, edx
    shr esi, 5
    mov edx, FOOD
    call cell
    add rsp, 8
    ret

msg_score db "snake: score ", 0
dir   db 0
want  db 0
head  dd 0
tail  dd 0
grow  dd 3
score dd 0
food  dd 0
next  dq 0
seed  dq 0
xs    times CAP db 0
ys    times CAP db 0
occ   times COLS * ROWS db 0
