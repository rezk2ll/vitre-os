; PS/2 mouse on IRQ 12, the i8042's second port, streaming 3-byte packets.
; mouse_x and mouse_y follow it in screen pixels, mouse_buttons holds its
; buttons (bit 0 left, 1 right, 2 middle) and mouse_moves counts packets.

MOUSE_TRIES equ 100000              ; polls before a silent controller is given up

; name: mouse_init
; in:   fb_init done, interrupts off
; out:  the mouse streaming and IRQ 12 unmasked; CF=1 if no mouse answered
; clobbers: caller-saved
mouse_init:
    sub rsp, 8
    cmp byte [rel console_ready], 0
    je .done                        ; no screen to point at
    call mouse_drain                ; a key pressed at boot is not the config byte
    mov rax, [rel fb_width]
    shr rax, 1
    mov [rel mouse_x], eax
    mov rax, [rel fb_height]
    shr rax, 1
    mov [rel mouse_y], eax
    mov al, 0xa8                    ; second port on
    call mouse_cmd
    jc .done
    mov al, 0x20                    ; read the configuration byte
    call mouse_cmd
    jc .done
    call mouse_in
    jc .done
    or al, 0x02                     ; its IRQ on
    and al, ~0x20                   ; its clock on
    mov [rsp], al
    mov al, 0x60
    call mouse_cmd
    jc .done
    mov al, [rsp]
    call mouse_out
    jc .done
    mov al, 0xf6                    ; defaults
    call mouse_send
    jc .done
    mov al, 0xf4                    ; stream
    call mouse_send
    jc .done
    call mouse_drain
    mov edi, IRQ_BASE + 12
    lea rsi, [rel mouse_irq]
    call isr_set_handler
    mov edi, 2                      ; the slave PIC's cascade
    call pic_unmask
    mov edi, 12
    call pic_unmask
    lea rdi, [rel mouse_msg_ready]
    call kputs
    clc
    jmp .out
.done:
    lea rdi, [rel mouse_msg_none]
    call kputs
    stc
.out:
    add rsp, 8
    ret

; name: mouse_drain
; in:   none
; out:  the controller's output buffer empty
; clobbers: rax
mouse_drain:
    in al, 0x64
    test al, 1
    jz .ret
    in al, 0x60
    jmp mouse_drain
.ret:
    ret

; name: mouse_send
; in:   al = a command for the mouse
; out:  sent and acknowledged; CF=1 if it was not
; clobbers: rax, rcx
mouse_send:
    push rax
    mov al, 0xd4                    ; the next data byte goes to the mouse
    call mouse_cmd
    pop rax
    jc .ret
    call mouse_out
    jc .ret
    call mouse_in
    jc .ret
    cmp al, 0xfa
    je .ret                         ; CF=0
    stc
.ret:
    ret

; name: mouse_cmd
; in:   al = controller command
; out:  written to port 0x64; CF=1 if the controller never took it
; clobbers: rcx
mouse_cmd:
    call mouse_wait_out
    jc .ret
    out 0x64, al
.ret:
    ret

; name: mouse_out
; in:   al = data byte
; out:  written to port 0x60; CF=1 if the controller never took it
; clobbers: rcx
mouse_out:
    call mouse_wait_out
    jc .ret
    out 0x60, al
.ret:
    ret

; name: mouse_wait_out
; in:   none
; out:  CF=0 once the controller's input buffer is empty
; clobbers: rcx
mouse_wait_out:
    push rax
    mov ecx, MOUSE_TRIES
.poll:
    in al, 0x64
    test al, 2
    jz .ok                          ; CF=0 from test
    dec ecx
    jnz .poll
    stc
.ok:
    pop rax
    ret

; name: mouse_in
; in:   none
; out:  al = the next byte from the controller; CF=1 if none came
; clobbers: rax, rcx
mouse_in:
    mov ecx, MOUSE_TRIES
.poll:
    in al, 0x64
    test al, 1
    jnz .read
    dec ecx
    jnz .poll
    stc
    ret
.read:
    in al, 0x60
    clc
    ret

; name: mouse_irq
; in:   rdi = frame
; out:  rax = frame; a complete packet moves mouse_x and mouse_y
; clobbers: caller-saved
mouse_irq:
    push rdi
    in al, 0x64
    and al, 0x21
    cmp al, 0x21                    ; a byte waiting, and it is the mouse's
    jne .eoi
    in al, 0x60
    movzx ecx, byte [rel mouse_have]
    test ecx, ecx
    jnz .store
    cmp al, 0xfa                    ; a late acknowledgement
    je .eoi
    test al, 0x08                   ; a first byte always has bit 3 set
    jz .eoi
.store:
    lea rdx, [rel mouse_packet]
    mov [rdx + rcx], al
    inc ecx
    cmp ecx, 3
    jb .keep
    call mouse_packet_done
    call cursor_off
    call cursor_on
    xor ecx, ecx
.keep:
    mov [rel mouse_have], cl
.eoi:
    mov edi, 12
    call pic_eoi
    pop rax
    ret

; name: mouse_packet_done
; in:   mouse_packet = flags, dx, dy
; out:  the position and buttons updated
; clobbers: rax, rdx, rsi
mouse_packet_done:
    movzx esi, byte [rel mouse_packet]
    test esi, 0xc0                  ; overflow: the deltas are junk
    jnz .ret
    test esi, 0x08                  ; out of step: a delta was taken as flags
    jz .ret
    mov eax, esi
    and eax, 7
    mov [rel mouse_buttons], al
    movzx eax, byte [rel mouse_packet + 1]
    test esi, 0x10
    jz .dx
    sub eax, 256
.dx:
    add eax, [rel mouse_x]
    mov rdx, [rel fb_width]
    call mouse_clamp
    mov [rel mouse_x], eax
    movzx eax, byte [rel mouse_packet + 2]
    test esi, 0x20
    jz .dy
    sub eax, 256
.dy:
    neg eax                         ; the mouse counts up, the screen down
    add eax, [rel mouse_y]
    mov rdx, [rel fb_height]
    call mouse_clamp
    mov [rel mouse_y], eax
    inc qword [rel mouse_moves]
.ret:
    ret

; name: mouse_clamp
; in:   eax = coordinate, edx = the screen's size along it
; out:  eax within 0 to edx - 1
; clobbers: rdx
mouse_clamp:
    test eax, eax
    jns .high
    xor eax, eax
.high:
    dec edx
    cmp eax, edx
    jle .ret
    mov eax, edx
.ret:
    ret

; name: cmd_mouse
; in:   rdi = arguments (ignored)
; out:  "mouse X Y buttons B" printed
; clobbers: caller-saved
cmd_mouse:
    sub rsp, 8
    lea rdi, [rel mouse_msg]
    call kputs
    mov edi, [rel mouse_x]
    call [rel jt_kput_dec]
    mov edi, ' '
    call kputc
    mov edi, [rel mouse_y]
    call [rel jt_kput_dec]
    lea rdi, [rel mouse_msg_buttons]
    call kputs
    movzx edi, byte [rel mouse_buttons]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    add rsp, 8
    ret

mouse_msg         db "mouse ", 0
mouse_msg_ready   db "[mouse] ready", 10, 0
mouse_msg_none    db "[mouse] no mouse", 10, 0
mouse_msg_buttons db " buttons ", 0

section .bss
alignb 8
mouse_moves   resq 1
mouse_x       resd 1
mouse_y       resd 1
mouse_packet  resb 3
mouse_have    resb 1
mouse_buttons resb 1
section .text
