; Kernel image, loaded by stage 2 at KERNEL_PHYS and entered in long mode
; with paging identity-mapping the first 4 GiB.
;
; Code and data live in .text. Zero-initialised state goes in .bss, which
; the bin format places after the image; kernel_entry clears it.

%include "boot/layout.inc"

bits 64
org KERNEL_PHYS
[map symbols build/kernel.map]
section .text
section .bss nobits align=16
bss_start:
section .text

kernel_entry:
    mov rsp, KERNEL_STACK_TOP
    cld
    mov rdi, bss_start
    mov rcx, bss_end
    sub rcx, rdi
    xor eax, eax
    rep stosb

    call fb_init
    jc .headless
    call klog_console_init
.headless:
    lea rdi, [rel msg_long_mode]
    call kputs
    cmp byte [rel console_ready], 0
    je .no_fb
    call [rel jt_fb_log_mode]
.no_fb:
    ; the last qword of the image proves stage 2 loaded all of it
    mov rax, KERNEL_END_MAGIC
    cmp [rel kernel_end_magic], rax
    lea rdi, [rel msg_image_ok]
    je .image_ok
    lea rdi, [rel msg_image_bad]
.image_ok:
    call kputs

    call fwcfg_read_cmdline
    lea rdi, [rel msg_cmdline]
    call kputs
    lea rdi, [rel kernel_cmdline]
    call kputs
    mov edi, 10
    call kputc

    call pmm_init
    call [rel jt_pmm_log]
    call idt_init
    call pic_init
    call pit_init
    call sched_init
    call debug_init
    call bp_init
    call src_load
    call patch_boot
    call kbd_init
    call net_init
    sti
    lea rdi, [rel msg_interrupts]
    call kputs
    cmp byte [rel net_ready], 0     ; net_init already said there is no card
    je .no_net
    call cmd_dhcp
.no_net:

    call kernel_selftests
    jmp shell_run

; name: kernel_selftests
; in:   none
; out:  runs the scenarios named on the command line (test=...)
; clobbers: caller-saved
kernel_selftests:
    sub rsp, 8
    lea rdi, [rel test_pit]
    call cmdline_has
    jnz .no_pit
    call selftest_pit
.no_pit:
    lea rdi, [rel test_ud]
    call cmdline_has
    jnz .no_ud
    ud2
.no_ud:
    lea rdi, [rel test_mem]
    call cmdline_has
    jnz .no_mem
    call selftest_mem
.no_mem:
    lea rdi, [rel test_tasks]
    call cmdline_has
    jnz .no_tasks
    call selftest_tasks
.no_tasks:
    lea rdi, [rel test_syms]
    call cmdline_has
    jnz .no_syms
    call sym_dump
.no_syms:
    add rsp, 8
    ret

; name: selftest_pit
; in:   none
; out:  logs the tick count three times, 100 ms apart
; clobbers: caller-saved
selftest_pit:
    push rbx
    mov ebx, 3
.again:
    mov edi, 100
    call timer_sleep_ms
    lea rdi, [rel msg_ticks]
    call kputs
    mov rdi, [rel timer_ticks]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    dec ebx
    jnz .again
    pop rbx
    ret

%include "drivers/serial.asm"
%include "kernel/log.asm"
%include "kernel/idt.asm"
%include "kernel/exception.asm"
%include "drivers/pic.asm"
%include "drivers/pit.asm"
%include "drivers/fwcfg.asm"
%include "lib/string.asm"
%include "drivers/fb.asm"
%include "glass/font.asm"
%include "glass/console.asm"
%include "drivers/keyboard.asm"
%include "kernel/pmm.asm"
%include "kernel/heap.asm"
%include "kernel/memtest.asm"
%include "kernel/sched.asm"
%include "kernel/tasktest.asm"
%include "kernel/debug.asm"
%include "kernel/breakpoint.asm"
%include "drivers/ata.asm"
%include "drivers/pci.asm"
%include "drivers/e1000.asm"
%include "net/net.asm"
%include "net/eth.asm"
%include "net/arp.asm"
%include "net/ipv4.asm"
%include "net/icmp.asm"
%include "net/udp.asm"
%include "net/dhcp.asm"
%include "net/dns.asm"
%include "net/tcp.asm"
%include "net/http.asm"
%include "apps/html.asm"
%include "apps/browser.asm"
%include "lib/sha256.asm"
%include "apps/crypto.asm"
%include "kernel/report.asm"
%include "kernel/symbols.asm"
%include "forge/lex.asm"
%include "forge/expr.asm"
%include "forge/forge.asm"
%include "forge/source.asm"
%include "forge/check.asm"
%include "forge/patch.asm"
%include "forge/guard.asm"
%include "forge/text.asm"
%include "forge/screen.asm"
%include "forge/editor.asm"
%include "forge/find.asm"
%include "forge/save.asm"
%include "forge/operand.asm"
%include "forge/encode.asm"
%include "forge/modrm.asm"
%include "forge/arith.asm"
%include "forge/unary.asm"
%include "forge/flow.asm"
%include "apps/shell.asm"
%include "apps/taskcmd.asm"
%include "glass/disfmt.asm"
%include "glass/dis.asm"
%include "glass/disops.asm"
%include "glass/disgrp.asm"
%include "glass/disext.asm"
%include "glass/discmd.asm"
%include "glass/panes.asm"
%include "glass/codepane.asm"
%include "glass/view.asm"
%include "glass/patchview.asm"

msg_long_mode  db "[boot] long mode ok", 10, 0
msg_image_ok   db "[kernel] image ok", 10, 0
msg_image_bad  db "[kernel] image truncated", 10, 0
msg_cmdline    db "[kernel] cmdline: ", 0
msg_interrupts db "[kernel] interrupts on", 10, 0
msg_ticks      db "[timer] ticks=", 0
test_pit       db "test=pit", 0
test_ud        db "test=ud", 0
test_mem       db "test=mem", 0
test_tasks     db "test=tasks", 0
test_syms      db "test=syms", 0

KERNEL_END_MAGIC equ 0x444e454552544956       ; "VITREEND"
align 8
kernel_end_magic dq KERNEL_END_MAGIC

section .bss
bss_end:
