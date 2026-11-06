; Interrupt descriptor table and the common interrupt entry path.
;
; Every vector pushes the same frame (see INT_FRAME_* below) and calls the
; handler registered in isr_handlers with rdi = frame. The handler returns in
; rax the frame to resume, which lets the scheduler switch tasks by returning
; another task's frame.

INT_FRAME_R15    equ 0
INT_FRAME_R14    equ 8
INT_FRAME_R13    equ 16
INT_FRAME_R12    equ 24
INT_FRAME_R11    equ 32
INT_FRAME_R10    equ 40
INT_FRAME_R9     equ 48
INT_FRAME_R8     equ 56
INT_FRAME_RBP    equ 64
INT_FRAME_RDI    equ 72
INT_FRAME_RSI    equ 80
INT_FRAME_RDX    equ 88
INT_FRAME_RCX    equ 96
INT_FRAME_RBX    equ 104
INT_FRAME_RAX    equ 112
INT_FRAME_VECTOR equ 120
INT_FRAME_ERROR  equ 128
INT_FRAME_RIP    equ 136
INT_FRAME_CS     equ 144
INT_FRAME_RFLAGS equ 152
INT_FRAME_RSP    equ 160
INT_FRAME_SS     equ 168
INT_FRAME_SIZE   equ 176

KERNEL_CS equ 0x18

; name: idt_init
; in:   none
; out:  IDT loaded, all 256 vectors point at their stubs
; clobbers: rax, rcx, rdx, rdi, rsi
idt_init:
    lea rdi, [rel idt_table]
    lea rsi, [rel isr_stub_table]
    xor ecx, ecx
.next:
    mov rax, [rsi + rcx * 8]
    mov [rdi], ax                   ; offset 15:0
    mov word [rdi + 2], KERNEL_CS
    mov word [rdi + 4], 0x8e00      ; present, DPL 0, interrupt gate
    shr rax, 16
    mov [rdi + 6], ax               ; offset 31:16
    shr rax, 16
    mov [rdi + 8], eax              ; offset 63:32
    mov dword [rdi + 12], 0
    add rdi, 16
    inc ecx
    cmp ecx, 256
    jb .next
    lidt [rel idt_desc]
    ret

; name: isr_set_handler
; in:   rdi = vector, rsi = handler (rdi = frame -> rax = frame to resume)
; out:  none
; clobbers: rax
isr_set_handler:
    lea rax, [rel isr_handlers]
    mov [rax + rdi * 8], rsi
    ret

isr_common:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    cld
    mov rdi, rsp
    mov rbx, [rsp + INT_FRAME_VECTOR]
    lea rax, [rel isr_handlers]
    mov rax, [rax + rbx * 8]
    test rax, rax
    jnz .call
    lea rax, [rel isr_default]
.call:
    call rax
    mov rsp, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    add rsp, 16                     ; vector, error code
    iretq

; name: isr_default
; in:   rdi = frame
; out:  rax = frame; exceptions dump registers and halt, IRQs are acknowledged
; clobbers: caller-saved
isr_default:
    mov rax, [rdi + INT_FRAME_VECTOR]
    cmp rax, 32
    jb exception_fatal
    cmp rax, 48
    jae .done
    push rdi
    mov rdi, rax
    sub rdi, 32
    call pic_eoi
    pop rdi
.done:
    mov rax, rdi
    ret

; Stubs: vectors with a CPU error code are 8, 10-14, 17, 21, 29, 30.
%macro ISR_STUB 1
isr_stub_%1:
%if %1 = 8 || (%1 >= 10 && %1 <= 14) || %1 = 17 || %1 = 21 || %1 = 29 || %1 = 30
%else
    push 0
%endif
    push %1
    jmp isr_common
%endmacro

%assign i 0
%rep 256
ISR_STUB %[i]
%assign i i + 1
%endrep

align 8
isr_stub_table:
%assign i 0
%rep 256
    dq isr_stub_%[i]
%assign i i + 1
%endrep

idt_desc:
    dw 256 * 16 - 1
    dq idt_table

section .bss
alignb 16
idt_table    resb 256 * 16
isr_handlers resq 256
section .text
