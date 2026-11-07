; `beep [hz]`: half a second of a square wave, 440 Hz by default.

BEEP_FRAMES equ AC97_RATE / 2
BEEP_PAGES  equ (BEEP_FRAMES * 4 + 4095) / 4096
BEEP_LEVEL  equ 6000

; name: cmd_beep
; in:   rdi = arguments: a pitch in Hz, 20 to 20000, or nothing
; out:  the tone played to its end
; clobbers: caller-saved
cmd_beep:
    push rbx
    push r12
    push r13
    lea rbx, [rel beep_msg_none]
    cmp byte [rel ac97_ready], 0
    je .say
    mov r12d, 440
    cmp byte [rdi], 0
    je .tone
    lea rbx, [rel beep_msg_usage]
    call parse_dec
    jc .say
    cmp rax, 20
    jb .say
    cmp rax, 20000
    ja .say
    mov r12d, eax
.tone:
    lea rbx, [rel beep_msg_memory]
    mov edi, BEEP_PAGES
    call page_alloc
    jc .say
    mov r13, rax
    mov eax, AC97_RATE / 2          ; frames between flips
    xor edx, edx
    div r12d
    mov r8d, eax
    mov r9d, eax
    mov r10d, BEEP_LEVEL
    mov rdi, r13
    mov ecx, BEEP_FRAMES
.fill:
    mov [rdi], r10w
    mov [rdi + 2], r10w
    add rdi, 4
    dec r9d
    jnz .same
    mov r9d, r8d
    neg r10d
.same:
    dec ecx
    jnz .fill
    mov rdi, r13
    mov esi, BEEP_FRAMES
    call ac97_queue
.wait:
    call task_yield
    call ac97_busy
    jc .wait
    mov rdi, r13
    mov esi, BEEP_PAGES
    call page_free
    lea rbx, [rel beep_msg_done]
.say:
    mov rdi, rbx
    call kputs
    pop r13
    pop r12
    pop rbx
    ret

beep_msg_none   db "[beep] no sound card", 10, 0
beep_msg_usage  db "usage: beep [hz], hz from 20 to 20000", 10, 0
beep_msg_memory db "[beep] not enough memory", 10, 0
beep_msg_done   db 0
