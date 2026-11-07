; Video player: `play <url>` streams a .viv video (see tools/vivenc.asm)
; over HTTP or HTTPS, one range request a chunk. A task fetches the next
; chunk while this one plays, into the other of two buffers: chunk k always
; lands in buffer k & 1. The picture is scaled up by a whole number to fill
; the screen. q or Esc stop it.

PLAY_CHUNK_MAX   equ 200000         ; with its headers, fits tcp_rx
PLAY_CHUNK_PAGES equ (PLAY_CHUNK_MAX + 4095) / 4096
PLAY_PIXELS_MAX  equ 640 * 480
PLAY_FRAME_PAGES equ PLAY_PIXELS_MAX / 4096
PLAY_SCALE_MAX   equ 8
PLAY_ROW_PAGES   equ PLAY_SCALE_MAX * 4 ; that many screen rows of 4096 pixels
PLAY_PAGES       equ PLAY_CHUNK_PAGES * 2 + PLAY_FRAME_PAGES + PLAY_ROW_PAGES
PLAY_HEADER      equ 16
PLAY_BUSY        equ 1              ; a buffer's state
PLAY_READY       equ 2
PLAY_END         equ 3

; name: cmd_play
; in:   rdi = arguments: the video's URL
; out:  the video played until its end, q or Esc; screen cleared and the
;       frames shown printed
; clobbers: caller-saved
cmd_play:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rbx, [rel play_msg_screen]
    cmp byte [rel console_ready], 0
    je .say
    lea rbx, [rel play_msg_net]
    cmp byte [rel net_ready], 0
    je .say
    lea rbx, [rel play_msg_usage]
    cmp byte [rdi], 0
    je .say
    mov [rel play_url], rdi         ; the shell keeps it until play returns
    lea rbx, [rel play_msg_memory]
    mov edi, PLAY_PAGES
    call page_alloc
    jc .say
    mov [rel play_mem], rax
    mov [rel play_buf], rax
    add rax, PLAY_CHUNK_PAGES * 4096
    mov [rel play_buf + 8], rax
    add rax, PLAY_CHUNK_PAGES * 4096
    mov [rel play_frame], rax
    add rax, PLAY_FRAME_PAGES * 4096
    mov [rel play_row], rax
    mov word [rel play_state], 0
    mov dword [rel play_chunk], PLAY_CHUNK_MAX
    xor edi, edi                    ; chunk 0, here: it says the rest
    call play_fetch
    lea rbx, [rel play_msg_bad]
    cmp byte [rel play_state], PLAY_READY
    jne .free
    call play_header
    jc .free
    call play_setup
    mov edi, 1
    call play_fetch_start
    xor r12d, r12d                  ; the buffer playing
    mov r13d, PLAY_HEADER           ; the next frame in it
    mov r14, [rel timer_ticks]      ; when frame 0 was due
    xor r15d, r15d                  ; frames shown
.frame:
    call kbd_poll
    jz .next
    cmp eax, 'q'
    je .stop
    cmp eax, KEY_ESC
    je .stop
.next:
    lea rax, [rel play_len]
    mov ecx, [rax + r12 * 4]
    lea eax, [r13 + 4]
    cmp eax, ecx
    ja .chunk
    lea rax, [rel play_buf]
    mov rsi, [rax + r12 * 8]
    add rsi, r13
    mov edx, [rsi]
    test edx, edx
    jz .chunk
    lea rax, [r13 + 4 + rdx]
    cmp rax, rcx
    ja .chunk
    mov r13d, eax
    add rsi, 4
    call play_decode
    mov eax, r15d                   ; wait for its time
    imul eax, eax, 1000
    xor edx, edx
    div dword [rel play_fps]
    lea rbx, [r14 + rax]
.due:
    cmp [rel timer_ticks], rbx
    jae .draw
    call task_yield
    jmp .due
.draw:
    call play_draw
    inc r15d
    jmp .frame
.chunk:
    xor r12d, 1
.wait:
    lea rax, [rel play_state]
    movzx eax, byte [rax + r12]
    cmp eax, PLAY_BUSY
    jne .waited
    call kbd_poll
    jz .yield
    cmp eax, 'q'
    je .stop
    cmp eax, KEY_ESC
    je .stop
.yield:
    call task_yield
    jmp .wait
.waited:
    cmp eax, PLAY_READY
    jne .stop                       ; the end of the video
    xor r13d, r13d
    mov edi, [rel play_next]        ; the chunk after this one, into the
    call play_fetch_start           ; buffer just played
    jmp .frame
.stop:
    call play_wait
    call shell_clear_screen
    lea rdi, [rel play_msg_done]
    call kputs
    mov edi, r15d
    call [rel jt_kput_dec]
    lea rbx, [rel play_msg_frames]
.free:
    call play_wait
    mov rdi, [rel play_mem]
    mov esi, PLAY_PAGES
    call page_free
.say:
    mov rdi, rbx
    call kputs
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: play_fetch_start
; in:   edi = chunk number
; out:  a task fetching it into buffer edi & 1, which is marked busy; it is
;       marked ended if no task could start
; clobbers: caller-saved
play_fetch_start:
    push rbx
    mov ebx, edi
    lea eax, [rbx + 1]
    mov [rel play_next], eax
    mov eax, ebx
    and eax, 1
    lea rcx, [rel play_state]
    mov byte [rcx + rax], PLAY_BUSY
    lea rdi, [rel play_fetch]
    lea rsi, [rel play_task_name]
    mov edx, ebx
    call task_create
    jnc .ret
    mov eax, ebx
    and eax, 1
    lea rcx, [rel play_state]
    mov byte [rcx + rax], PLAY_END
.ret:
    pop rbx
    ret

; name: play_fetch
; in:   edi = chunk number
; out:  the chunk in buffer edi & 1 and that buffer ready, or marked ended
;       when there is no such chunk or the fetch failed
; clobbers: caller-saved
play_fetch:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, edi
    and r12d, 1                     ; the buffer
    mov eax, [rel play_chunk]
    imul rax, rbx
    mov [rel http_range_from], rax
    mov ecx, [rel play_chunk]
    lea rax, [rax + rcx - 1]
    mov [rel http_range_to], rax
    mov rdi, [rel play_url]
    call http_get
    jc .end
    cmp dword [rel tcp_rx + 8], " 206"
    je .take
    test ebx, ebx                   ; a server that ignores ranges sends the
    jnz .end                        ; whole video: only its start is used
    cmp dword [rel tcp_rx + 8], " 200"
    jne .end
.take:
    call http_body
    cmp ecx, [rel play_chunk]
    jbe .copy
    mov ecx, [rel play_chunk]
.copy:
    lea rdx, [rel play_len]
    mov [rdx + r12 * 4], ecx
    mov rsi, rax
    lea rax, [rel play_buf]
    mov rdi, [rax + r12 * 8]
    rep movsb
    mov al, PLAY_READY
    jmp .set
.end:
    mov al, PLAY_END
.set:
    lea rcx, [rel play_state]
    mov [rcx + r12], al
    add rsp, 8
    pop r12
    pop rbx
    ret

; name: play_wait
; in:   none
; out:  no fetch task running, so the buffers can go
; clobbers: caller-saved
play_wait:
    sub rsp, 8
.check:
    cmp byte [rel play_state], PLAY_BUSY
    je .yield
    cmp byte [rel play_state + 1], PLAY_BUSY
    jne .ret
.yield:
    call task_yield
    jmp .check
.ret:
    add rsp, 8
    ret

; name: play_header
; in:   chunk 0 in buffer 0
; out:  play_w, play_h, play_fps, play_chunk and play_pixels set from its
;       header; CF=1 if it is not a video this player can show
; clobbers: rax, rcx, rdx, rsi
play_header:
    mov rsi, [rel play_buf]
    cmp dword [rel play_len], PLAY_HEADER
    jb .bad
    cmp dword [rsi], "VIV1"
    jne .bad
    movzx eax, word [rsi + 4]
    mov [rel play_w], eax
    movzx ecx, word [rsi + 6]
    mov [rel play_h], ecx
    imul eax, ecx
    test eax, eax
    jz .bad
    cmp eax, PLAY_PIXELS_MAX
    ja .bad
    mov [rel play_pixels], eax
    mov eax, [rel play_w]
    cmp rax, [rel fb_width]
    ja .bad
    cmp rcx, [rel fb_height]
    ja .bad
    movzx eax, word [rsi + 8]
    test eax, eax
    jz .bad
    mov [rel play_fps], eax
    mov eax, [rsi + 12]
    cmp eax, 1024
    jb .bad
    cmp eax, PLAY_CHUNK_MAX
    ja .bad
    mov [rel play_chunk], eax
    cmp [rel play_len], eax
    jbe .ok
    mov [rel play_len], eax
.ok:
    clc
    ret
.bad:
    stc
    ret

; name: play_setup
; in:   the header read
; out:  the palette, the scale and the picture's place set, the screen
;       black, the frame black
; clobbers: caller-saved
play_setup:
    lea rdi, [rel play_palette]     ; colour byte rrrgggbb to 0x00rrggbb
    xor ecx, ecx
.colour:
    mov eax, ecx
    shr eax, 5
    imul eax, eax, 255
    xor edx, edx
    mov esi, 7
    div esi
    shl eax, 16
    mov r8d, eax
    mov eax, ecx
    shr eax, 2
    and eax, 7
    imul eax, eax, 255
    xor edx, edx
    div esi
    shl eax, 8
    or r8d, eax
    mov eax, ecx
    and eax, 3
    imul eax, eax, 85
    or eax, r8d
    stosd
    inc ecx
    cmp ecx, 256
    jb .colour
    mov rax, [rel fb_width]
    xor edx, edx
    div qword [rel play_w]
    mov ecx, eax
    mov rax, [rel fb_height]
    xor edx, edx
    div qword [rel play_h]
    cmp eax, ecx
    cmova eax, ecx
    cmp eax, PLAY_SCALE_MAX
    jbe .scale
    mov eax, PLAY_SCALE_MAX
.scale:
    mov [rel play_scale], eax
    mov ecx, [rel play_w]
    imul ecx, eax
    mov [rel play_span], ecx
    mov rdx, [rel fb_width]
    sub rdx, rcx
    shr rdx, 1
    mov [rel play_x], edx
    imul eax, [rel play_h]
    mov rdx, [rel fb_height]
    sub rdx, rax
    shr rdx, 1
    mov [rel play_y], edx
    mov rdi, [rel play_frame]
    mov ecx, [rel play_pixels]
    xor eax, eax
    rep stosb
    xor edi, edi
    xor esi, esi
    mov rdx, [rel fb_width]
    mov rcx, [rel fb_height]
    xor r8d, r8d
    jmp fb_fill_rect

; name: play_decode
; in:   rsi = a frame's codes, edx = their length
; out:  play_frame updated; a code that runs past the frame or the codes
;       ends the frame there
; clobbers: rax, rcx, rdx, rsi, rdi, r8, r9, r10
play_decode:
    lea r8, [rsi + rdx]             ; the codes' end
    xor r9d, r9d                    ; pixel
    mov r10d, [rel play_pixels]
.code:
    cmp rsi, r8
    jae .ret
    movzx eax, byte [rsi]
    inc rsi
    mov ecx, eax
    and ecx, 63
    inc ecx
    lea edx, [r9 + rcx]
    cmp edx, r10d
    ja .ret
    mov rdi, [rel play_frame]
    add rdi, r9
    mov r9d, edx
    shr eax, 6
    jz .code                        ; keep
    cmp eax, 2
    je .copy
    ja .ret
    cmp rsi, r8
    jae .ret
    lodsb
    rep stosb
    jmp .code
.copy:
    lea rdx, [rsi + rcx]
    cmp rdx, r8
    ja .ret
    rep movsb
    jmp .code
.ret:
    ret

; name: play_draw
; in:   play_frame
; out:  the frame drawn, each pixel a play_scale square
; clobbers: caller-saved
play_draw:
    push rbx
    push r12
    push r13
    mov rbx, [rel play_frame]
    mov r12d, [rel play_y]
    xor r13d, r13d                  ; frame row
.row:
    cmp r13d, [rel play_h]
    jae .ret
    mov rdi, [rel play_row]         ; one screen row
    mov rsi, rbx
    mov ecx, [rel play_w]
    lea r8, [rel play_palette]
.px:
    movzx eax, byte [rsi]
    inc rsi
    mov eax, [r8 + rax * 4]
    mov edx, [rel play_scale]
.wide:
    stosd
    dec edx
    jnz .wide
    dec ecx
    jnz .px
    mov eax, [rel play_scale]       ; then scale - 1 copies under it
    dec eax
    imul eax, [rel play_span]
    mov ecx, eax
    mov rsi, [rel play_row]
    rep movsd
    mov edi, [rel play_x]
    mov esi, r12d
    mov edx, [rel play_span]
    mov ecx, [rel play_scale]
    mov r8, [rel play_row]
    call fb_blit
    add r12d, [rel play_scale]
    mov eax, [rel play_w]
    add rbx, rax
    inc r13d
    jmp .row
.ret:
    pop r13
    pop r12
    pop rbx
    ret

play_task_name  db "play fetch", 0
play_msg_usage  db "usage: play http://host/video.viv", 10, 0
play_msg_screen db "[play] needs the screen", 10, 0
play_msg_net    db "[play] needs the network", 10, 0
play_msg_memory db "[play] not enough memory", 10, 0
play_msg_bad    db "[play] no Vitre video there", 10, 0
play_msg_done   db "[play] ", 0
play_msg_frames db " frames", 10, 0

section .bss
alignb 8
play_mem     resq 1
play_url     resq 1
play_buf     resq 2
play_frame   resq 1
play_row     resq 1
play_w       resq 1                 ; qwords: divisors of fb_width, fb_height
play_h       resq 1
play_len     resd 2                 ; bytes in each buffer
play_fps     resd 1
play_chunk   resd 1
play_pixels  resd 1
play_scale   resd 1
play_span    resd 1                 ; screen pixels a row
play_x       resd 1
play_y       resd 1
play_next    resd 1                 ; the next chunk to fetch
play_palette resd 256
play_state   resb 2
section .text
