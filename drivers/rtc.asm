; CMOS real-time clock, read as UTC (QEMU's default base). The time is kept
; as a 14-digit string "YYYYMMDDHHMMSS", which compares in order with the
; dates in certificates.

RTC_INDEX  equ 0x70
RTC_DATA   equ 0x71
RTC_STAMP  equ 14

; name: rtc_reg
; in:   dil = register
; out:  al = its value, in binary
; clobbers: rax, rcx
rtc_reg:
    mov al, dil
    out RTC_INDEX, al
    in al, RTC_DATA
    ; fall through

; name: rtc_binary
; in:   al = a clock register's value
; out:  al in binary
; clobbers: rax, rcx
rtc_binary:
    test byte [rel rtc_bcd], 1
    jz .ret
    mov cl, al                      ; BCD: tens in the high nibble
    shr al, 4
    imul eax, eax, 10
    and cl, 0x0f
    add al, cl
.ret:
    ret

; name: rtc_read
; in:   none
; out:  rtc_now = the time as "YYYYMMDDHHMMSS"
; clobbers: rax, rcx, rdx, rdi, rsi
rtc_read:
    pushfq
    cli                             ; reads stay inside the 244 us UIP promises
    mov al, 0x0b                    ; status B: bit 2 binary, bit 1 24-hour
    out RTC_INDEX, al
    in al, RTC_DATA
    mov [rel rtc_mode], al
    not al
    shr al, 2
    and al, 1
    mov [rel rtc_bcd], al
.wait:
    mov al, 0x0a                    ; status A: an update is under way
    out RTC_INDEX, al
    in al, RTC_DATA
    test al, 0x80
    jnz .wait
    lea rsi, [rel rtc_now]
    mov edi, 0x32                   ; century
    call rtc_reg
    cmp al, 19
    jae .century
    mov al, 20                      ; no century register: assume 20xx
.century:
    call rtc_put2
    lea rdx, [rel rtc_fields]
.field:
    movzx edi, byte [rdx]
    cmp edi, 0xff
    je .done
    cmp edi, 4
    je .hour
    call rtc_reg
.put:
    call rtc_put2
    inc rdx
    jmp .field
.hour:
    call rtc_hour
    jmp .put
.done:
    popfq
    ret

; name: rtc_hour
; in:   rtc_mode = status B
; out:  al = the hour, 0 to 23
; clobbers: rax, rcx
rtc_hour:
    mov al, 4
    out RTC_INDEX, al
    in al, RTC_DATA
    test byte [rel rtc_mode], 2
    jnz rtc_binary                  ; 24-hour mode
    push rax
    and al, 0x7f                    ; bit 7 is PM
    call rtc_binary
    cmp al, 12
    jne .pm
    xor eax, eax                    ; 12 AM is 0
.pm:
    pop rcx
    test cl, 0x80
    jz .ret
    add al, 12
.ret:
    ret

; name: rtc_put2
; in:   al = 0 to 99, rsi = output
; out:  two digits written, rsi past them
; clobbers: rax, rcx
rtc_put2:
    movzx eax, al
    mov cl, 10
    div cl
    add ax, '00'
    mov [rsi], ax
    add rsi, 2
    ret

; name: cmd_date
; in:   rdi = arguments (ignored)
; out:  the date and time printed as "YYYY-MM-DD HH:MM:SS UTC"
; clobbers: caller-saved
cmd_date:
    push rbx
    call rtc_read
    lea rsi, [rel rtc_now]
    lea rdi, [rel rtc_text]
    lea rbx, [rel rtc_layout]
.copy:
    movzx eax, byte [rbx]
    inc rbx
    test eax, eax
    jz .print
    cmp al, '#'
    jne .put
    mov al, [rsi]
    inc rsi
.put:
    stosb
    jmp .copy
.print:
    mov byte [rdi], 0
    lea rdi, [rel rtc_text]
    call kputs
    pop rbx
    ret

rtc_fields db 9, 8, 7, 4, 2, 0, 0xff ; year, month, day, hour, minute, second
rtc_layout db "####-##-## ##:##:## UTC", 10, 0

section .bss
rtc_bcd    resb 1
rtc_mode   resb 1
rtc_now    resb RTC_STAMP
rtc_text   resb 32
section .text
