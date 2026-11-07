; Video encoder, a Linux x86-64 program run on the build machine. It reads
; raw RGB frames on stdin and writes a Vitre video (.viv) on stdout:
;
;   ffmpeg -i clip.mp4 -vf scale=320:180,fps=15 -f rawvideo -pix_fmt rgb24 - \
;     | build/vivenc 320 180 15 > clip.viv
;
; A .viv file starts with a 16-byte header: "VIV1", then width, height and
; frames a second as 16-bit numbers, 2 zero bytes, and the chunk size as a
; 32-bit number. The file is cut in chunks of that size, the header inside
; the first, so a player can fetch chunk k with one HTTP range request.
; A chunk holds whole frames, each a 32-bit length and its codes; a length
; of 0, or the chunk's end, ends the chunk.
;
; A frame is codes over its pixels, left to right and top to bottom, each
; pixel one byte of red 3 bits, green 3 bits, blue 2 bits. A code byte's
; low 6 bits are n - 1 for n from 1 to 64; its top 2 bits say what to do:
; 00 keeps n pixels of the frame before (black before the first), 01 sets
; n pixels to the byte after the code, 10 sets n pixels to the n bytes
; after the code.

BITS 64
default rel

SYS_READ   equ 0
SYS_WRITE  equ 1
SYS_EXIT   equ 60

HEADER     equ 16
MAX_PIXELS equ 640 * 480
MAX_CHUNK  equ 200000               ; the player fetches a chunk in one read
CHUNK      equ 131072
OP_RUN     equ 0x40
OP_COPY    equ 0x80

section .text
global _start
_start:
    mov rbx, rsp
    cmp qword [rbx], 4
    jb .usage
    mov rdi, [rbx + 16]
    call parse
    mov [width], eax
    mov rdi, [rbx + 24]
    call parse
    mov [height], eax
    mov rdi, [rbx + 32]
    call parse
    mov [fps], eax
    mov dword [chunk], CHUNK
    cmp qword [rbx], 5
    jb .check
    mov rdi, [rbx + 40]
    call parse
    mov [chunk], eax
.check:
    mov eax, [width]
    imul eax, [height]
    test eax, eax
    jz .usage
    cmp eax, MAX_PIXELS
    ja .usage
    mov [pixels], eax
    cmp dword [fps], 0
    je .usage
    cmp dword [chunk], 1024
    jb .usage
    cmp dword [chunk], MAX_CHUNK
    ja .usage
    lea rdi, [outbuf]                  ; the header opens the first chunk
    mov dword [rdi], "VIV1"
    mov eax, [width]
    mov [rdi + 4], ax
    mov eax, [height]
    mov [rdi + 6], ax
    mov eax, [fps]
    mov [rdi + 8], ax
    mov word [rdi + 10], 0
    mov eax, [chunk]
    mov [rdi + 12], eax
    mov dword [fill], HEADER
.frame:
    call read_frame
    jc .end
    call convert
    call encode
    call pack
    jmp .frame
.end:
    mov edx, [fill]
    call flush
    xor edi, edi
    mov eax, SYS_EXIT
    syscall
.usage:
    lea rsi, [msg_usage]
    mov edx, msg_usage_len
    jmp fail

; name: parse
; in:   rdi = decimal string
; out:  eax = its value, 0 if it holds anything but digits
; clobbers: rax, rcx, rdi
parse:
    xor eax, eax
.digit:
    movzx ecx, byte [rdi]
    test ecx, ecx
    jz .ret
    sub ecx, '0'
    cmp ecx, 9
    ja .bad
    imul eax, eax, 10
    add eax, ecx
    inc rdi
    jmp .digit
.bad:
    xor eax, eax
.ret:
    ret

; name: read_frame
; in:   none
; out:  rgb holds the next frame; CF=1 at the end of the input
; clobbers: rax, rcx, rdx, rsi, rdi, r11
read_frame:
    mov ecx, [pixels]
    imul ecx, ecx, 3
    mov [want], ecx
    xor ecx, ecx                    ; bytes read so far
.read:
    push rcx
    lea rsi, [rgb + rcx]
    mov edx, [want]
    sub edx, ecx
    xor edi, edi
    mov eax, SYS_READ
    syscall
    pop rcx
    test rax, rax
    jle .short
    add ecx, eax
    cmp ecx, [want]
    jb .read
    clc
    ret
.short:
    stc                             ; a part frame at the end is dropped
    ret

; name: convert
; in:   rgb = a frame
; out:  cur = its pixels as one byte each
; clobbers: rax, rcx, rdx, rsi, rdi
convert:
    lea rsi, [rgb]
    lea rdi, [cur]
    mov ecx, [pixels]
.px:
    movzx eax, byte [rsi]           ; red, 3 bits
    and eax, 0xe0
    movzx edx, byte [rsi + 1]       ; green, 3 bits
    shr edx, 3
    and edx, 0x1c
    or eax, edx
    movzx edx, byte [rsi + 2]       ; blue, 2 bits
    shr edx, 6
    or eax, edx
    stosb
    add rsi, 3
    dec ecx
    jnz .px
    ret

; name: encode
; in:   cur = this frame
; out:  codes holds the frame's codes, code_len their length
; clobbers: rax, rcx, rdx, rsi, rdi, r8, r9, r10
encode:
    lea rsi, [cur]
    lea rdi, [codes]
    xor ecx, ecx                    ; pixel
    mov r9d, [pixels]
.code:
    cmp ecx, r9d
    jae .done
    call run_length
    cmp r8d, 3
    jb .copy
    lea eax, [r8 - 1 + OP_RUN]
    stosb
    mov al, [rsi + rcx]
    stosb
    add ecx, r8d
    jmp .code
.copy:                              ; copy bytes up to a run
    xor r8d, r8d
.copy_more:
    inc r8d
    lea r10d, [rcx + r8]
    cmp r10d, r9d
    jae .copy_out
    cmp r8d, 64
    jae .copy_out
    push rcx
    mov ecx, r10d
    push r8
    call run_length
    mov eax, r8d
    pop r8
    pop rcx
    cmp eax, 3
    jae .copy_out
    jmp .copy_more
.copy_out:
    lea eax, [r8 - 1 + OP_COPY]
    stosb
    push rsi
    push rcx
    add rsi, rcx
    mov ecx, r8d
    rep movsb
    pop rcx
    pop rsi
    add ecx, r8d
    jmp .code
.done:
    lea rax, [codes]
    sub rdi, rax
    mov [code_len], edi
    ret

; name: run_length
; in:   rsi = cur, ecx = pixel, r9d = pixels
; out:  r8d = how many pixels from ecx on share its value, at most 64
; clobbers: rax, r8, r10
run_length:
    mov r8d, 1
    mov al, [rsi + rcx]
.more:
    cmp r8d, 64
    jae .ret
    lea r10d, [rcx + r8]
    cmp r10d, r9d
    jae .ret
    cmp al, [rsi + r10]
    jne .ret
    inc r8d
    jmp .more
.ret:
    ret

; name: pack
; in:   codes, code_len = a frame
; out:  the frame added to the chunk in out; a full chunk is padded with
;       zeros, written, and the frame starts the next one
; clobbers: caller-saved
pack:
    mov eax, [code_len]
    add eax, 4
    mov ecx, [chunk]
    sub ecx, [fill]
    cmp eax, ecx
    jbe .add
    mov edx, [chunk]
    sub edx, HEADER
    cmp eax, edx
    ja .big                         ; it would not fit even in the first chunk
    lea rdi, [outbuf]
    add edi, [fill]
    xor eax, eax
    rep stosb
    mov edx, [chunk]
    call flush
    mov dword [fill], 0
.add:
    lea rdi, [outbuf]
    mov eax, [fill]
    add rdi, rax
    mov eax, [code_len]
    stosd
    lea rsi, [codes]
    mov ecx, eax
    rep movsb
    lea rax, [outbuf]
    sub rdi, rax
    mov [fill], edi
    ret
.big:
    lea rsi, [msg_big]
    mov edx, msg_big_len
    jmp fail

; name: flush
; in:   edx = bytes of out to write
; out:  written to stdout
; clobbers: rax, rcx, rdx, rsi, rdi, r11
flush:
    lea rsi, [outbuf]
.write:
    test edx, edx
    jz .ret
    push rdx
    push rsi
    mov edi, 1
    mov eax, SYS_WRITE
    syscall
    pop rsi
    pop rdx
    test rax, rax
    jle .error
    add rsi, rax
    sub edx, eax
    jmp .write
.ret:
    ret
.error:
    lea rsi, [msg_write]
    mov edx, msg_write_len
    ; fall through

; name: fail
; in:   rsi = message, edx = its length
; out:  the message on stderr, then exit status 1
fail:
    mov edi, 2
    mov eax, SYS_WRITE
    syscall
    mov edi, 1
    mov eax, SYS_EXIT
    syscall

section .data
msg_usage   db "usage: vivenc width height fps [chunk] < rgb24 frames > video.viv", 10
msg_usage_len equ $ - msg_usage
msg_big     db "vivenc: a frame does not fit in a chunk; use a bigger chunk", 10
msg_big_len equ $ - msg_big
msg_write   db "vivenc: cannot write the output", 10
msg_write_len equ $ - msg_write

section .bss
width    resd 1
height   resd 1
fps      resd 1
chunk    resd 1
pixels   resd 1
want     resd 1
fill     resd 1
code_len resd 1
rgb      resb MAX_PIXELS * 3
cur      resb MAX_PIXELS
codes    resb MAX_PIXELS + MAX_PIXELS / 64 + 64
outbuf   resb MAX_CHUNK
