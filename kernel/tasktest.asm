; Scheduler self-test (test=tasks): two tasks print in turns while the boot
; task waits for both to end, then lists the task table.

TASKTEST_LINES equ 5

; name: selftest_tasks
; in:   scheduler running
; out:  "[alpha] n" and "[beta] n" lines interleaved, then "[sched] tasks done"
; clobbers: caller-saved
selftest_tasks:
    sub rsp, 8
    lea rdi, [rel tasktest_body]
    lea rsi, [rel tasktest_alpha]
    mov rdx, rsi
    call task_create
    jc .fail
    lea rdi, [rel tasktest_body]
    lea rsi, [rel tasktest_beta]
    mov rdx, rsi
    call task_create
    jc .fail
.wait:
    call task_yield
    cmp dword [rel tasktest_finished], 2
    jb .wait
    call task_yield                 ; lets the scheduler reap both stacks
    call [rel jt_sched_list]
    lea rdi, [rel tasktest_msg_done]
    call kputs
    add rsp, 8
    ret
.fail:
    lea rdi, [rel tasktest_msg_fail]
    call kputs
    add rsp, 8
    ret

; name: tasktest_body
; in:   rdi = task name
; out:  prints "[name] 0" to "[name] 4", 20 ms apart, then ends
tasktest_body:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    xor r12d, r12d
.line:
    cli                             ; a switch mid-line would mix the two tasks' text
    lea rdi, [rel tasktest_buf_open]
    call kputs
    mov rdi, rbx
    call kputs
    lea rdi, [rel tasktest_buf_close]
    call kputs
    mov edi, r12d
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
    sti
    mov edi, 20
    call timer_sleep_ms
    inc r12d
    cmp r12d, TASKTEST_LINES
    jb .line
    lock inc dword [rel tasktest_finished]
    add rsp, 8
    pop r12
    pop rbx
    ret

tasktest_alpha     db "alpha", 0
tasktest_beta      db "beta", 0
tasktest_buf_open  db "[", 0
tasktest_buf_close db "] ", 0
tasktest_msg_done  db "[sched] tasks done", 10, 0
tasktest_msg_fail  db "[sched] FAIL task_create", 10, 0

section .bss
tasktest_finished resd 1
section .text
