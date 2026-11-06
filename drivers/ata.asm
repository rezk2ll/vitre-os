; ATA PIO on the primary IDE channel, master drive, LBA28, polled.

ATA_DATA    equ 0x1f0
ATA_COUNT   equ 0x1f2
ATA_LBA0    equ 0x1f3
ATA_LBA1    equ 0x1f4
ATA_LBA2    equ 0x1f5
ATA_DRIVE   equ 0x1f6
ATA_CMD     equ 0x1f7               ; status on read
ATA_CTRL    equ 0x3f6

ATA_SR_ERR  equ 0x01
ATA_SR_DRQ  equ 0x08
ATA_SR_DF   equ 0x20
ATA_SR_BSY  equ 0x80

ATA_CMD_READ  equ 0x20
ATA_CMD_WRITE equ 0x30
ATA_CMD_FLUSH equ 0xe7

; name: ata_read
; in:   rdi = LBA, rsi = sector count (1-256), rdx = buffer
; out:  sectors in the buffer, CF=1 on a drive error
; clobbers: rax, rcx, rdx, rdi, rsi, r8
ata_read:
    mov r8, rdx
    mov ecx, ATA_CMD_READ
    call ata_command
    jc .done
    mov rdi, r8
.sector:
    call ata_wait_drq
    jc .done
    mov ecx, 256
    mov dx, ATA_DATA
    rep insw
    dec esi
    jnz .sector
    clc
.done:
    ret

; name: ata_write
; in:   rdi = LBA, rsi = sector count (1-256), rdx = buffer
; out:  sectors written and the drive cache flushed, CF=1 on a drive error
; clobbers: rax, rcx, rdx, rdi, rsi, r8
ata_write:
    mov r8, rdx
    mov ecx, ATA_CMD_WRITE
    call ata_command
    jc .done
    xchg rsi, r8                    ; rsi = buffer, r8d = sectors left
.sector:
    call ata_wait_drq
    jc .done
    mov ecx, 256
    mov dx, ATA_DATA
    rep outsw
    dec r8d
    jnz .sector
    mov dx, ATA_CMD
    mov al, ATA_CMD_FLUSH
    out dx, al
    call ata_wait_idle
.done:
    ret

; name: ata_command
; in:   rdi = LBA, esi = sector count (256 is sent as 0), ecx = command
; out:  command issued, CF=1 if the drive stays busy or reports an error
; clobbers: rax, rdx
ata_command:
    call ata_wait_idle
    jc .done
    mov dx, ATA_DRIVE
    mov rax, rdi
    shr rax, 24
    and al, 0x0f
    or al, 0xe0                     ; LBA mode, master
    out dx, al
    mov dx, ATA_COUNT
    mov eax, esi
    out dx, al
    mov dx, ATA_LBA0
    mov rax, rdi
    out dx, al
    mov dx, ATA_LBA1
    shr rax, 8
    out dx, al
    mov dx, ATA_LBA2
    shr rax, 8
    out dx, al
    mov dx, ATA_CMD
    mov eax, ecx
    out dx, al
    clc
.done:
    ret

; name: ata_wait_idle
; in:   none
; out:  CF=1 on error or if BSY never clears
; clobbers: rax, rdx
ata_wait_idle:
    push rcx
    mov ecx, 1000000
    mov dx, ATA_CMD
.poll:
    in al, dx
    test al, ATA_SR_BSY
    jz .ready
    dec ecx
    jnz .poll
    jmp .fail
.ready:
    test al, ATA_SR_ERR | ATA_SR_DF
    jnz .fail
    pop rcx
    clc
    ret
.fail:
    pop rcx
    stc
    ret

; name: ata_wait_drq
; in:   none
; out:  drive ready to move one sector, CF=1 on error or timeout
; clobbers: rax, rdx
ata_wait_drq:
    push rcx
    mov dx, ATA_CTRL                ; four alternate status reads, about 400 ns
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    mov ecx, 1000000
    mov dx, ATA_CMD
.poll:
    in al, dx
    test al, ATA_SR_ERR | ATA_SR_DF
    jnz .fail
    test al, ATA_SR_BSY
    jnz .next
    test al, ATA_SR_DRQ
    jnz .ready
.next:
    dec ecx
    jnz .poll
.fail:
    pop rcx
    stc
    ret
.ready:
    pop rcx
    clc
    ret
