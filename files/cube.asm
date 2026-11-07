; cube.asm: a wireframe cube turning in 3D, with integer maths only. Edit
; SIZE, DIST, the colours or the turn speeds and run it again.
; q or Esc leaves.
; Try: run cube.asm

VIEW  equ 512                       ; the square the cube is drawn in
HALF  equ 256
PAGES equ 256                       ; VIEW * VIEW pixels of 4 bytes
BAND  equ 64                        ; rows per copy to the screen
SIZE  equ 120                       ; half an edge
DIST  equ 420                       ; from the eye to the cube's centre
FOCAL equ 400
BG    equ 0x002e3440
COS1  equ 1073721611                ; cos and sin of 2 pi / 1024, times 2^30
SIN1  equ 6588356

start:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov edi, PAGES
    call page_alloc
    jc .done
    mov [rel buf], rax
    call make_sines
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov rcx, [rel fb_height]
    mov r8d, BG
    call fb_fill_rect
.frame:
    call clear
    call turn
    call edges
    call show
    add qword [rel yaw], 3
    add qword [rel pitch], 2
    mov edi, 16
    call timer_sleep_ms
    call kbd_poll
    jz .frame
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    jne .frame
.quit:
    mov rdi, [rel buf]
    mov esi, PAGES
    call page_free
    call shell_clear_screen
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sines[i] = sin(2 pi i / 1024) * 2^14, by turning the point (1, 0) one
; step at a time with 2^30 fixed point, which keeps the error tiny
make_sines:
    push rbx
    mov r8, 0x40000000
    xor r9d, r9d
    lea rbx, [rel sines]
    xor ecx, ecx
.next:
    mov rax, r9
    sar rax, 16
    mov [rbx + rcx * 8], rax
    mov rax, r8
    imul rax, rax, COS1
    mov rdx, r9
    imul rdx, rdx, SIN1
    sub rax, rdx
    mov r10, r8
    imul r10, r10, SIN1
    mov rdx, r9
    imul rdx, rdx, COS1
    add rdx, r10
    sar rax, 30
    sar rdx, 30
    mov r8, rax
    mov r9, rdx
    inc ecx
    cmp ecx, 1024
    jb .next
    pop rbx
    ret

; px[i], py[i]: corner i of the cube, turned by yaw about the vertical axis
; and by pitch about the horizontal one, then put in perspective
turn:
    push rbx
    push r12
    push r13
    lea rbx, [rel sines]
    mov rax, [rel yaw]
    and eax, 1023
    mov r8, [rbx + rax * 8]         ; sin yaw
    add eax, 256
    and eax, 1023
    mov r9, [rbx + rax * 8]         ; cos yaw
    mov rax, [rel pitch]
    and eax, 1023
    mov r10, [rbx + rax * 8]        ; sin pitch
    add eax, 256
    and eax, 1023
    mov r11, [rbx + rax * 8]        ; cos pitch
    xor r12d, r12d
.corner:
    mov esi, r12d                   ; x, y, z: bits 0, 1, 2 of the corner
    and esi, 1
    imul rsi, rsi, SIZE * 2
    sub rsi, SIZE
    mov edi, r12d
    shr edi, 1
    and edi, 1
    imul rdi, rdi, SIZE * 2
    sub rdi, SIZE
    mov ecx, r12d
    shr ecx, 2
    imul rcx, rcx, SIZE * 2
    sub rcx, SIZE
    mov rax, rsi                    ; about the vertical axis
    imul rax, r9
    mov rdx, rcx
    imul rdx, r8
    sub rax, rdx
    sar rax, 14
    mov r13, rax
    imul rsi, r8
    imul rcx, r9
    add rcx, rsi
    sar rcx, 14
    mov rax, rdi                    ; about the horizontal axis
    imul rax, r11
    mov rdx, rcx
    imul rdx, r10
    sub rax, rdx
    sar rax, 14
    mov rsi, rax
    imul rdi, r10
    imul rcx, r11
    add rcx, rdi
    sar rcx, 14
    add rcx, DIST
    mov rax, r13
    imul rax, rax, FOCAL
    mov rdx, rax
    sar rdx, 63
    idiv rcx
    add rax, HALF
    lea rdx, [rel px]
    mov [rdx + r12 * 8], rax
    mov rax, rsi
    imul rax, rax, FOCAL
    mov rdx, rax
    sar rdx, 63
    idiv rcx
    add rax, HALF
    lea rdx, [rel py]
    mov [rdx + r12 * 8], rax
    inc r12d
    cmp r12d, 8
    jb .corner
    pop r13
    pop r12
    pop rbx
    ret

; the 12 edges: each corner joined to the corners one bit away, coloured
; by the axis the edge runs along
edges:
    push rbx
    push r12
    push r13
    xor r12d, r12d
.corner:
    mov r13d, 1
.bit:
    test r12d, r13d
    jnz .next_bit
    mov ebx, r12d
    or ebx, r13d
    lea rcx, [rel px]
    mov rdi, [rcx + r12 * 8]
    mov rdx, [rcx + rbx * 8]
    lea rcx, [rel py]
    mov rsi, [rcx + r12 * 8]
    mov rcx, [rcx + rbx * 8]
    lea rax, [rel colours]
    mov r8d, [rax + r13 * 4]
    call line
.next_bit:
    shl r13d, 1
    cmp r13d, 8
    jb .bit
    inc r12d
    cmp r12d, 8
    jb .corner
    pop r13
    pop r12
    pop rbx
    ret

; line from (rdi, rsi) to (rdx, rcx) in colour r8d, two pixels thick, by
; Bresenham: err tracks how far the drawn point is from the true line
line:
    push r12
    push r13
    push r14
    push r15
    mov r11, [rel buf]
    mov r9, rdx                     ; dx = |x1 - x0|, r12 = its sign
    sub r9, rdi
    mov r12d, 1
    jns .dx_ok
    xor eax, eax
    sub rax, r9
    mov r9, rax
    xor r12d, r12d
    dec r12
.dx_ok:
    mov r10, rcx                    ; dy = -|y1 - y0|, r13 = its sign
    sub r10, rsi
    mov r13d, 1
    js .dy_neg
    xor eax, eax
    sub rax, r10
    mov r10, rax
    jmp .dy_ok
.dy_neg:
    xor r13d, r13d
    dec r13
.dy_ok:
    lea r14, [r9 + r10]
.plot:
    cmp rdi, VIEW - 1
    jae .moved
    cmp rsi, VIEW - 1
    jae .moved
    mov rax, rsi
    imul rax, rax, VIEW
    add rax, rdi
    mov [r11 + rax * 4], r8d
    mov [r11 + rax * 4 + 4], r8d
    mov [r11 + rax * 4 + VIEW * 4], r8d
    mov [r11 + rax * 4 + VIEW * 4 + 4], r8d
.moved:
    cmp rdi, rdx
    jne .step
    cmp rsi, rcx
    je .done
.step:
    lea r15, [r14 + r14]
    cmp r15, r10
    jl .no_x
    add r14, r10
    add rdi, r12
.no_x:
    cmp r15, r9
    jg .plot
    add r14, r9
    add rsi, r13
    jmp .plot
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

clear:
    mov rdi, [rel buf]
    mov ecx, VIEW * HALF            ; two pixels a store
    mov eax, BG
    mov rdx, rax
    shl rdx, 32
    or rax, rdx
.next:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .next
    ret

; the view copied to the middle of the screen a band at a time, so
; interrupts are never off for long
show:
    push rbx
    push r12
    push r13
    xor ebx, ebx
.band:
    mov rdi, [rel fb_width]
    sub rdi, VIEW
    shr rdi, 1
    mov rsi, [rel fb_height]
    sub rsi, VIEW
    shr rsi, 1
    add rsi, rbx
    mov edx, VIEW
    mov ecx, BAND
    mov r8, rbx
    imul r8, r8, VIEW * 4
    add r8, [rel buf]
    call fb_blit
    add ebx, BAND
    cmp ebx, VIEW
    jb .band
    pop r13
    pop r12
    pop rbx
    ret

buf     dq 0
yaw     dq 0
pitch   dq 0
colours dd 0, 0x00bf616a, 0x00a3be8c, 0, 0x0088c0d0
px      times 64 db 0
py      times 64 db 0
sines   times 8192 db 0
