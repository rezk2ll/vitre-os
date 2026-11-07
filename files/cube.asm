; cube.asm: a solid cube turning in 3D, lit from the top left, with integer
; maths only. Edit SIZE, DIST, the light, the colours or the turn speeds
; and run it again.
; q or Esc leaves.
; Try: run cube.asm

VIEW    equ 512                     ; the square the cube is drawn in
HALF    equ 256
PIXELS  equ VIEW * VIEW * 4
SPANS   equ PIXELS                  ; then each row's left and right edge
RIGHTS  equ PIXELS + VIEW * 8
PAGES   equ 258
BAND    equ 64                      ; rows per copy to the screen
SIZE    equ 120                     ; half an edge
DIST    equ 420                     ; from the eye to the cube's centre
FOCAL   equ 400
BG      equ 0x002e3440
COS1    equ 1073721611              ; cos and sin of 2 pi / 1024, times 2^30
SIN1    equ 6588356
LX      equ -102                    ; towards the light, 256 long; y is down
LY      equ -154
LZ      equ -179
NLEN    equ 4 * SIZE * SIZE         ; a face's normal is two edges crossed
AMBIENT equ 70                      ; out of 256: light a face gets anyway
DIFFUSE equ 186

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
    call faces
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

; corner i of the cube, turned by yaw about the vertical axis and by pitch
; about the horizontal one: qx[i], qy[i], qz[i] from the cube's centre,
; and px[i], py[i] in perspective on the view
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
    lea rdx, [rel qx]
    mov [rdx + r12 * 8], r13
    lea rdx, [rel qy]
    mov [rdx + r12 * 8], rsi
    lea rdx, [rel qz]
    mov [rdx + r12 * 8], rcx
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

; each face that looks at the eye, filled in its colour times its light.
; A convex solid needs no depth test: the faces that look away are hidden.
faces:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r12, [rel face_list]
    mov r13d, 6
.face:
    movzx eax, byte [r12]           ; the normal: two edges from corner 0
    movzx ecx, byte [r12 + 1]
    call vector
    mov r14, r8
    mov r15, r9
    mov rbx, r10
    movzx eax, byte [r12]
    movzx ecx, byte [r12 + 3]
    call vector
    mov rax, r15
    imul rax, r10
    mov rdx, rbx
    imul rdx, r9
    sub rax, rdx
    mov [rel nx], rax
    mov rax, rbx
    imul rax, r8
    mov rdx, r14
    imul rdx, r10
    sub rax, rdx
    mov [rel ny], rax
    mov rax, r14
    imul rax, r9
    mov rdx, r15
    imul rdx, r8
    sub rax, rdx
    mov [rel nz], rax
    movzx eax, byte [r12]           ; twice the face's centre: corners 0 + 2
    movzx ecx, byte [r12 + 2]
    lea rdx, [rel qx]
    mov r8, [rdx + rax * 8]
    add r8, [rdx + rcx * 8]
    lea rdx, [rel qy]
    mov r9, [rdx + rax * 8]
    add r9, [rdx + rcx * 8]
    lea rdx, [rel qz]
    mov r10, [rdx + rax * 8]
    add r10, [rdx + rcx * 8]
    call dot
    test rax, rax
    jns .outward
    neg rax                         ; turn the normal out of the cube
    neg qword [rel nx]
    neg qword [rel ny]
    neg qword [rel nz]
.outward:
    mov rdx, [rel nz]               ; seen if the normal points at the eye
    imul rdx, rdx, DIST * 2
    add rax, rdx
    jns .next
    mov r8, LX
    mov r9, LY
    mov r10, LZ
    call dot
    test rax, rax
    jns .lit
    xor eax, eax
.lit:
    imul rax, rax, DIFFUSE
    xor edx, edx
    mov ecx, NLEN * 256
    div rcx
    add rax, AMBIENT
    cmp rax, 256
    jbe .shade
    mov eax, 256
.shade:
    mov r9d, eax
    mov ecx, [r12 + 4]
    mov eax, ecx                    ; each channel times the light / 256
    and eax, 0xff
    imul eax, r9d
    shr eax, 8
    mov r8d, eax
    mov eax, ecx
    shr eax, 8
    and eax, 0xff
    imul eax, r9d
    and eax, 0xff00
    or r8d, eax
    mov eax, ecx
    shr eax, 16
    and eax, 0xff
    imul eax, r9d
    shl eax, 8
    and eax, 0xff0000
    or r8d, eax
    call fill
.next:
    add r12, 8
    dec r13d
    jnz .face
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; r8, r9, r10 = corner ecx minus corner eax, from qx, qy, qz
vector:
    lea rdx, [rel qx]
    mov r8, [rdx + rcx * 8]
    sub r8, [rdx + rax * 8]
    lea rdx, [rel qy]
    mov r9, [rdx + rcx * 8]
    sub r9, [rdx + rax * 8]
    lea rdx, [rel qz]
    mov r10, [rdx + rcx * 8]
    sub r10, [rdx + rax * 8]
    ret

; rax = (nx, ny, nz) . (r8, r9, r10)
dot:
    mov rax, [rel nx]
    imul rax, r8
    mov rdx, [rel ny]
    imul rdx, r9
    add rax, rdx
    mov rdx, [rel nz]
    imul rdx, r10
    add rax, rdx
    ret

; the face at r12 filled in colour r8d: each of its four edges widens the
; spans of the rows it crosses, then each row's span is painted
fill:
    push rbx
    push r13
    push r14
    push r15
    mov r13d, r8d
    mov r14, VIEW                   ; the rows it covers, r14 to r15
    mov r15, -1
    xor ebx, ebx
.range:
    movzx eax, byte [r12 + rbx]
    lea rdx, [rel py]
    mov rax, [rdx + rax * 8]
    cmp rax, r14
    jge .not_top
    mov r14, rax
.not_top:
    cmp rax, r15
    jle .not_bottom
    mov r15, rax
.not_bottom:
    inc ebx
    cmp ebx, 4
    jb .range
    test r14, r14
    jns .top_in
    xor r14d, r14d
.top_in:
    cmp r15, VIEW - 1
    jle .bottom_in
    mov r15, VIEW - 1
.bottom_in:
    cmp r14, r15
    jg .done
    mov rdx, [rel buf]
    mov r10, r14
.reset:
    mov rax, VIEW
    mov [rdx + r10 * 8 + SPANS], rax
    mov rax, -1
    mov [rdx + r10 * 8 + RIGHTS], rax
    inc r10
    cmp r10, r15
    jle .reset
    xor ebx, ebx
.edge:
    movzx eax, byte [r12 + rbx]
    lea ecx, [rbx + 1]
    and ecx, 3
    movzx ecx, byte [r12 + rcx]
    lea rdx, [rel px]
    mov rdi, [rdx + rax * 8]
    mov r8, [rdx + rcx * 8]
    lea rdx, [rel py]
    mov rsi, [rdx + rax * 8]
    mov r9, [rdx + rcx * 8]
    call span_edge
    inc ebx
    cmp ebx, 4
    jb .edge
    mov rdx, [rel buf]
    mov r10, r14
.row:
    mov rdi, [rdx + r10 * 8 + SPANS]
    mov rcx, [rdx + r10 * 8 + RIGHTS]
    test rdi, rdi
    jns .left_in
    xor edi, edi
.left_in:
    cmp rcx, VIEW - 1
    jle .right_in
    mov rcx, VIEW - 1
.right_in:
    cmp rdi, rcx
    jg .next_row
    mov rax, r10
    imul rax, rax, VIEW
    add rdi, rax
    add rcx, rax
.px:
    mov [rdx + rdi * 4], r13d
    inc rdi
    cmp rdi, rcx
    jle .px
.next_row:
    inc r10
    cmp r10, r15
    jle .row
.done:
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

; the edge (rdi, rsi) to (r8, r9) widens the spans of rows r14 to r15
span_edge:
    cmp rsi, r9
    jle .down
    mov rax, rdi                    ; from the top end
    mov rdi, r8
    mov r8, rax
    mov rax, rsi
    mov rsi, r9
    mov r9, rax
.down:
    mov r10, rsi
    cmp r10, r14
    jge .first
    mov r10, r14
.first:
    mov r11, r9
    cmp r11, r15
    jle .row
    mov r11, r15
.row:
    cmp r10, r11
    jg .ret
    mov rcx, r9
    sub rcx, rsi
    jz .flat
    mov rax, r8                     ; x0 + (x1 - x0) * (y - y0) / (y1 - y0)
    sub rax, rdi
    mov rdx, r10
    sub rdx, rsi
    imul rax, rdx
    mov rdx, rax
    sar rdx, 63
    idiv rcx
    add rax, rdi
    call widen
    jmp .next
.flat:
    mov rax, rdi
    call widen
    mov rax, r8
    call widen
.next:
    inc r10
    jmp .row
.ret:
    ret

; row r10's span grown to take x = rax
widen:
    mov rdx, [rel buf]
    cmp rax, [rdx + r10 * 8 + SPANS]
    jge .right
    mov [rdx + r10 * 8 + SPANS], rax
.right:
    cmp rax, [rdx + r10 * 8 + RIGHTS]
    jle .ret
    mov [rdx + r10 * 8 + RIGHTS], rax
.ret:
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

; each face: its corners in order round it, then its colour; a corner's
; bits 0, 1, 2 are its x, y, z
face_list:
    db 0, 2, 6, 4
    dd 0x00bf616a
    db 1, 3, 7, 5
    dd 0x00bf616a
    db 0, 1, 5, 4
    dd 0x00a3be8c
    db 2, 3, 7, 6
    dd 0x00a3be8c
    db 0, 1, 3, 2
    dd 0x0088c0d0
    db 4, 5, 7, 6
    dd 0x0088c0d0

buf     dq 0
yaw     dq 0
pitch   dq 0
nx      dq 0
ny      dq 0
nz      dq 0
px      times 64 db 0
py      times 64 db 0
qx      times 64 db 0
qy      times 64 db 0
qz      times 64 db 0
sines   times 8192 db 0
