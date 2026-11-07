; Persistence: `save` writes the source area back to disk; at boot, every
; module edited before a save is patched from its saved source.

; name: src_save
; in:   none
; out:  the source area written to its disk sectors; CF=1 on a disk error
; clobbers: caller-saved
src_save:
    mov rdx, [rel src_area]
    test rdx, rdx
    jz .fail
    mov rsi, [rel src_length]
    add rsi, 511
    shr rsi, 9
    mov edi, SRC_LBA
.chunk:
    push rdi
    push rsi
    push rdx
    cmp rsi, 256
    jbe .last
    mov esi, 256
.last:
    call ata_write
    pop rdx
    pop rsi
    pop rdi
    jc .fail
    add rdi, 256
    add rdx, 256 * 512
    sub rsi, 256
    jg .chunk
    clc
    ret
.fail:
    stc
    ret

; name: cmd_save
; in:   rdi = arguments (ignored)
; out:  source area on disk, result on the log
; clobbers: caller-saved
cmd_save:
    sub rsp, 8
    call src_save
    jc .failed
    lea rdi, [rel save_msg_done]
    call kputs
    mov rdi, [rel src_length]
    call [rel jt_kput_dec]
    lea rdi, [rel src_msg_bytes]
    call kputs
    add rsp, 8
    ret
.failed:
    lea rdi, [rel save_msg_failed]
    call kputs
    add rsp, 8
    ret

; name: patch_boot
; in:   source area loaded
; out:  every module marked edited in the source area patched live
; clobbers: caller-saved
patch_boot:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, [rel src_area]
    test rbx, rbx
    jz .done
    mov r12d, [rbx + SRC_HDR_COUNT]
    lea rbx, [rbx + SRC_DIR]
.entry:
    test r12d, r12d
    jz .done
    cmp dword [rbx + SRC_DIR_FLAGS], 0
    je .next
    mov rdi, rbx
    call patch_apply
.next:
    add rbx, SRC_DIR_ENTRY
    dec r12d
    jmp .entry
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

save_msg_done   db "[save] source area written, ", 0
save_msg_failed db "[save] disk write failed", 10, 0
