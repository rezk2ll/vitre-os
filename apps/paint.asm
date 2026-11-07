; Paint: `paint` turns the screen into a sheet of paper under a bar of
; colours. The left button draws in the colour picked from the bar, the
; right one rubs out; [ and ] change the brush, c clears, q or Esc leave.

PT_BAR      equ 24
PT_STEP     equ 26                  ; from one swatch to the next
PT_SWATCH_W equ 20
PT_SWATCH_H equ 16
PT_COLOURS  equ 10
PT_HINT_X   equ 8 + PT_COLOURS * PT_STEP + 16
PT_PAPER    equ 0x00ffffff
PT_BRUSH    equ 6
PT_BRUSH_MIN equ 2
PT_BRUSH_MAX equ 32
PT_NONE     equ -1

; name: cmd_paint
; in:   rdi = arguments (ignored)
; out:  painted until q or Esc; screen cleared
; clobbers: caller-saved
cmd_paint:
    push rbx
    push r12
    push r13
    cmp byte [rel console_ready], 0
    je .no_screen
    mov dword [rel pt_colour], 0
    mov dword [rel pt_brush], PT_BRUSH
    call pt_clear
    mov r12d, PT_NONE               ; where the last dab went, if the
    xor r13d, r13d                  ; button is still down
.loop:
    call kbd_poll
    jz .mouse
    cmp eax, 'q'
    je .quit
    cmp eax, KEY_ESC
    je .quit
    cmp eax, 'c'
    jne .smaller
    call pt_clear
    jmp .loop
.smaller:
    mov ecx, [rel pt_brush]
    cmp eax, '['
    jne .bigger
    sub ecx, 2
    cmp ecx, PT_BRUSH_MIN
    jl .loop
    jmp .brush
.bigger:
    cmp eax, ']'
    jne .loop
    add ecx, 2
    cmp ecx, PT_BRUSH_MAX
    jg .loop
.brush:
    mov [rel pt_brush], ecx
    call pt_bar
    jmp .loop
.mouse:
    movzx ebx, byte [rel mouse_buttons]
    test ebx, 3
    jz .up
    mov edi, [rel mouse_x]
    mov esi, [rel mouse_y]
    cmp esi, PT_BAR
    jb .pick
    mov eax, PT_PAPER
    test ebx, 1
    jz .ink
    mov eax, [rel pt_colour]
    lea rcx, [rel pt_colours]
    mov eax, [rcx + rax * 4]
.ink:
    mov [rel pt_ink], eax
    cmp r12d, PT_NONE
    jne .line
    mov r12d, edi                   ; a new stroke starts with a dot
    mov r13d, esi
.line:
    mov edx, r12d
    mov ecx, r13d
    mov r12d, edi
    mov r13d, esi
    call pt_line
    jmp .idle
.pick:
    test ebx, 1
    jz .up
    sub edi, 8                      ; the swatch under the pointer, if any
    jl .up
    mov eax, edi
    xor edx, edx
    mov ecx, PT_STEP
    div ecx
    cmp edx, PT_SWATCH_W
    jae .up
    cmp eax, PT_COLOURS
    jae .up
    cmp eax, [rel pt_colour]
    je .up
    mov [rel pt_colour], eax
    call pt_bar
.up:
    mov r12d, PT_NONE
.idle:
    call task_yield
    jmp .loop
.quit:
    call shell_clear_screen
    jmp .done
.no_screen:
    lea rdi, [rel pt_msg_no_screen]
    call kputs
.done:
    pop r13
    pop r12
    pop rbx
    ret

; name: pt_clear
; in:   none
; out:  the paper blank and the bar drawn
; clobbers: caller-saved
pt_clear:
    sub rsp, 8
    xor edi, edi
    mov esi, PT_BAR
    mov rdx, [rel fb_width]
    mov rcx, [rel fb_height]
    sub rcx, PT_BAR
    mov r8d, PT_PAPER
    call fb_fill_rect
    call pt_bar
    add rsp, 8
    ret

; name: pt_bar
; in:   pt_colour, pt_brush
; out:  the bar: the swatches, the picked one outlined, the brush and keys
; clobbers: caller-saved
pt_bar:
    push rbx
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov ecx, PT_BAR
    mov r8d, DT_BAR_BG
    call fb_fill_rect
    mov eax, [rel pt_colour]        ; the outline, under the picked swatch
    imul edi, eax, PT_STEP
    add edi, 8 - 2
    mov esi, (PT_BAR - PT_SWATCH_H) / 2 - 2
    mov edx, PT_SWATCH_W + 4
    mov ecx, PT_SWATCH_H + 4
    mov r8d, DT_TEXT
    call fb_fill_rect
    xor ebx, ebx
.swatch:
    imul edi, ebx, PT_STEP
    add edi, 8
    mov esi, (PT_BAR - PT_SWATCH_H) / 2
    mov edx, PT_SWATCH_W
    mov ecx, PT_SWATCH_H
    lea rax, [rel pt_colours]
    mov r8d, [rax + rbx * 4]
    call fb_fill_rect
    inc ebx
    cmp ebx, PT_COLOURS
    jb .swatch
    lea rdi, [rel pt_hint_text]     ; "brush N  " then the keys
    lea rsi, [rel pt_msg_brush]
.copy:
    lodsb
    stosb
    test al, al
    jnz .copy
    dec rdi
    mov esi, [rel pt_brush]
    call str_put_dec
    lea rsi, [rel pt_msg_keys]
.keys:
    lodsb
    stosb
    test al, al
    jnz .keys
    mov edi, PT_HINT_X
    mov esi, 4
    lea rdx, [rel pt_hint_text]
    mov ecx, DT_TEXT
    mov r8d, DT_BAR_BG
    call dt_text
    pop rbx
    ret

; name: pt_line
; in:   edi, esi = where the stroke is now; edx, ecx = where it was
; out:  dabs of the brush in pt_ink along the way, so a fast stroke has no
;       holes
; clobbers: caller-saved
pt_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12d, edx                   ; from
    mov r13d, ecx
    mov r14d, edi                   ; the way: to minus from
    sub r14d, edx
    mov r15d, esi
    sub r15d, ecx
    mov eax, r14d                   ; steps: the longer of |dx| and |dy|
    cdq
    xor eax, edx
    sub eax, edx
    mov ebx, eax
    mov eax, r15d
    cdq
    xor eax, edx
    sub eax, edx
    cmp eax, ebx
    jbe .steps
    mov ebx, eax
.steps:
    mov dword [rsp], 0
.dab:
    mov edi, r12d
    mov esi, r13d
    test ebx, ebx
    jz .at
    mov eax, r14d                   ; from + way * i / steps
    imul eax, [rsp]
    cdq
    idiv ebx
    add edi, eax
    mov eax, r15d
    imul eax, [rsp]
    cdq
    idiv ebx
    add esi, eax
.at:
    call pt_dab
    inc dword [rsp]
    cmp [rsp], ebx
    jbe .dab
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: pt_dab
; in:   edi, esi = a point on the paper
; out:  a square of the brush's size in pt_ink round it, kept on the paper
; clobbers: caller-saved
pt_dab:
    mov ecx, [rel pt_brush]
    mov eax, ecx
    shr eax, 1
    sub edi, eax
    jns .left
    xor edi, edi
.left:
    mov rax, [rel fb_width]
    sub eax, ecx
    cmp edi, eax
    jle .right
    mov edi, eax
.right:
    mov eax, ecx
    shr eax, 1
    sub esi, eax
    cmp esi, PT_BAR
    jge .top
    mov esi, PT_BAR
.top:
    mov rax, [rel fb_height]
    sub eax, ecx
    cmp esi, eax
    jle .bottom
    mov esi, eax
.bottom:
    mov edx, ecx
    mov r8d, [rel pt_ink]
    jmp fb_fill_rect

pt_colours dd 0x00000000, 0x00bf616a, 0x00d08770, 0x00ebcb8b, 0x00a3be8c
           dd 0x0088c0d0, 0x005e81ac, 0x00b48ead, 0x004c566a, 0x008b5a2b
pt_msg_no_screen db "[paint] needs the screen", 10, 0
pt_msg_brush db "brush ", 0
pt_msg_keys  db "   left draws, right rubs out, [ ] brush, c clears, q quits", 0

section .bss
pt_colour    resd 1                 ; the picked swatch
pt_brush     resd 1                 ; the brush's side in pixels
pt_ink       resd 1
pt_hint_text resb 96
section .text
