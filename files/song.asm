; song.asm: a tune on the sound card. Each note is a pitch in Hz (0 rests)
; and a length in steps of 150 ms; change them and run it again.
; q or Esc stops it.
; Try: run song.asm

HALF  equ 24000                     ; half the card's 48000 frames a second
STEP  equ 7200                      ; frames a step: 150 ms
LEVEL equ 5000                      ; loudness at a note's start
PIECE equ 24000                     ; frames a buffer handed to the card

start:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi, [rel no_card]
    cmp byte [rel ac97_ready], 0
    je .say
    xor r12d, r12d                  ; frames in the whole tune
    lea rbx, [rel notes]
.length:
    mov eax, [rbx + 4]
    test eax, eax
    jz .measured
    imul eax, eax, STEP
    add r12d, eax
    add rbx, 8
    jmp .length
.measured:
    lea rdi, [rel no_memory]
    mov eax, r12d
    shl eax, 2
    add eax, 4095
    shr eax, 12
    mov r15d, eax                   ; pages
    mov edi, eax
    call page_alloc
    jc .say
    mov r13, rax
    mov rdi, rax
    lea rbx, [rel notes]
.note:
    mov ecx, [rbx + 4]
    test ecx, ecx
    jz .rendered
    imul ecx, ecx, STEP
    mov esi, [rbx]
    call tone
    add rbx, 8
    jmp .note
.rendered:
    lea rdi, [rel playing]
    call kputs
    mov r14, r13                    ; the next frame to hand over
.queue:
    test r12d, r12d
    jz .wait
    mov esi, PIECE
    cmp r12d, esi
    jae .piece
    mov esi, r12d
.piece:
    mov rdi, r14
    push rsi
    call ac97_queue
    pop rsi
    jc .full
    sub r12d, esi
    lea r14, [r14 + rsi * 4]
    jmp .queue
.full:                              ; a long tune waits for room
    call task_yield
    jmp .queue
.wait:
    call kbd_poll
    jz .busy
    cmp eax, 'q'
    je .stop
    cmp eax, KEY_ESC
    je .stop
.busy:
    call task_yield
    call ac97_busy
    jc .wait
    lea rdi, [rel done]
    jmp .free
.stop:
    call ac97_stop
    lea rdi, [rel stopped]
.free:
    push rdi
    mov rdi, r13
    mov esi, r15d
    call page_free
    pop rdi
.say:
    call kputs
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ecx frames of a square wave at esi Hz (0: silence) from rdi on, fading
; out so each note is heard on its own; rdi ends after them
tone:
    push r12
    mov r8d, ecx                    ; frames left
    mov r9d, ecx                    ; the note's length
    mov r10d, 1                     ; frames until the wave flips
    mov r11d, 1                     ; the wave's sign
    xor r12d, r12d                  ; frames between flips, 0 for silence
    test esi, esi
    jz .frame
    mov eax, HALF
    xor edx, edx
    div esi
    mov r12d, eax
    mov r10d, eax
.frame:
    mov eax, r8d                    ; LEVEL * frames left / length
    imul eax, eax, LEVEL
    xor edx, edx
    div r9d
    test r12d, r12d
    jnz .sign
    xor eax, eax
.sign:
    imul eax, r11d
    mov [rdi], ax
    mov [rdi + 2], ax
    add rdi, 4
    dec r10d
    jnz .next
    mov r10d, r12d
    neg r11d
.next:
    dec r8d
    jnz .frame
    pop r12
    ret

no_card   db "song: no sound card", 10, 0
no_memory db "song: not enough memory", 10, 0
playing   db "song: playing, q stops it", 10, 0
done      db "song: done", 10, 0
stopped   db "song: stopped", 10, 0

notes:
    dd 330, 2, 392, 2, 523, 2, 392, 2, 440, 2, 523, 2, 659, 4
    dd 587, 2, 523, 2, 440, 2, 392, 2, 330, 2, 392, 2, 440, 4
    dd 349, 2, 440, 2, 523, 2, 440, 2, 392, 2, 330, 2, 294, 4
    dd 330, 2, 392, 2, 587, 2, 494, 2, 523, 8, 0, 2
    dd 0, 0
