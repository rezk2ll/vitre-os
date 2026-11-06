; Preemptive round-robin scheduler for kernel tasks. A task is its saved
; interrupt frame: switching is returning another task's frame from an
; interrupt handler (D6). The PIT preempts every SCHED_SLICE ms and
; `int SCHED_YIELD_VECTOR` gives up the rest of a slice.

TASK_FRAME  equ 0                   ; saved frame pointer, valid while not running
TASK_STATE  equ 8
TASK_STACK  equ 16                  ; stack pages, 0 for the boot task
TASK_TICKS  equ 24                  ; timer ticks spent running
TASK_NAME   equ 32                  ; up to 15 bytes, zero-terminated
TASK_SIZE   equ 48

TASK_FREE   equ 0
TASK_READY  equ 1
TASK_DEAD   equ 2

MAX_TASKS   equ 32
TASK_STACK_PAGES equ 4
SCHED_SLICE equ 10
SCHED_YIELD_VECTOR equ 0x40
KERNEL_DS   equ 0x10

; name: sched_init
; in:   idt_init done
; out:  the running boot code becomes task 0 "kernel", yield vector set
; clobbers: caller-saved
sched_init:
    sub rsp, 8
    lea rdi, [rel sched_tasks]
    mov qword [rdi + TASK_STATE], TASK_READY
    mov dword [rdi + TASK_NAME], "kern"
    mov word [rdi + TASK_NAME + 4], "el"
    mov edi, SCHED_YIELD_VECTOR
    lea rsi, [rel sched_switch]
    call isr_set_handler
    mov dword [rel sched_slice_left], SCHED_SLICE
    mov byte [rel sched_on], 1
    add rsp, 8
    ret

; name: task_create
; in:   rdi = entry, rsi = name, rdx = argument passed in rdi
; out:  rax = task id, CF=1 if no slot or no memory; the entry may return,
;       which ends the task
; clobbers: caller-saved
task_create:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    pushfq
    cli
    lea rbx, [rel sched_tasks + TASK_SIZE]
    mov r15d, 1
.slot:
    cmp qword [rbx + TASK_STATE], TASK_FREE
    je .found
    add rbx, TASK_SIZE
    inc r15d
    cmp r15d, MAX_TASKS
    jb .slot
    jmp .fail
.found:
    mov edi, TASK_STACK_PAGES
    call page_alloc
    jc .fail
    mov [rbx + TASK_STACK], rax
    lea rdx, [rax + TASK_STACK_PAGES * PAGE_SIZE - 8]
    lea rcx, [rel task_exit]
    mov [rdx], rcx                  ; returning from the entry ends the task
    lea rdi, [rdx - INT_FRAME_SIZE]
    mov [rbx + TASK_FRAME], rdi
    mov ecx, INT_FRAME_SIZE / 8
    xor eax, eax
    rep stosq
    mov rdi, [rbx + TASK_FRAME]
    mov [rdi + INT_FRAME_RIP], r12
    mov qword [rdi + INT_FRAME_CS], KERNEL_CS
    mov qword [rdi + INT_FRAME_RFLAGS], 0x202     ; IF set
    mov [rdi + INT_FRAME_RSP], rdx
    mov qword [rdi + INT_FRAME_SS], KERNEL_DS
    mov [rdi + INT_FRAME_RDI], r14
    mov qword [rbx + TASK_TICKS], 0
    lea rdi, [rbx + TASK_NAME]
    mov ecx, 15
.name:
    mov al, [r13]
    test al, al
    jz .name_end
    stosb
    inc r13
    dec ecx
    jnz .name
.name_end:
    mov byte [rdi], 0
    mov qword [rbx + TASK_STATE], TASK_READY
    popfq
    mov eax, r15d
    clc
    jmp .done
.fail:
    popfq
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name: task_exit
; in:   none, runs on the ending task
; out:  never returns; the scheduler frees the stack after switching away
task_exit:
    cli
    mov eax, [rel sched_current]
    imul eax, TASK_SIZE
    lea rcx, [rel sched_tasks]
    mov qword [rcx + rax + TASK_STATE], TASK_DEAD
    int SCHED_YIELD_VECTOR
.never:
    hlt
    jmp .never

; name: task_yield
; in:   none
; out:  other ready tasks run first
; clobbers: none
task_yield:
    int SCHED_YIELD_VECTOR
    ret

; name: sched_tick
; in:   rdi = frame of the interrupted task (timer IRQ, EOI sent)
; out:  rax = frame to resume
; clobbers: caller-saved
sched_tick:
    mov rax, rdi
    cmp byte [rel sched_on], 0
    je .done
    mov ecx, [rel sched_current]
    imul ecx, TASK_SIZE
    lea rdx, [rel sched_tasks]
    inc qword [rdx + rcx + TASK_TICKS]
    dec dword [rel sched_slice_left]
    jz sched_switch
.done:
    ret

; name: sched_switch
; in:   rdi = frame of the current task
; out:  rax = frame of the next ready task; dead tasks' stacks are freed
; clobbers: caller-saved
sched_switch:
    push rbx
    push r12
    push r13
    mov dword [rel sched_slice_left], SCHED_SLICE
    lea rbx, [rel sched_tasks]
    mov r12d, [rel sched_current]
    mov eax, r12d
    imul eax, TASK_SIZE
    mov [rbx + rax + TASK_FRAME], rdi
    mov r13d, r12d
.next:
    inc r13d
    cmp r13d, MAX_TASKS
    jb .check
    xor r13d, r13d
.check:
    mov eax, r13d
    imul eax, TASK_SIZE
    cmp qword [rbx + rax + TASK_STATE], TASK_READY
    je .picked
    cmp qword [rbx + rax + TASK_STATE], TASK_DEAD
    jne .skip
    cmp r13d, r12d                  ; still on this stack, free it later
    je .skip
    mov rdi, [rbx + rax + TASK_STACK]
    mov qword [rbx + rax + TASK_STATE], TASK_FREE
    mov esi, TASK_STACK_PAGES
    call page_free
.skip:
    cmp r13d, r12d
    jne .next
    jmp .picked                     ; nothing else is ready
.picked:
    mov [rel sched_current], r13d
    mov eax, r13d
    imul eax, TASK_SIZE
    mov rax, [rbx + rax + TASK_FRAME]
    pop r13
    pop r12
    pop rbx
    ret

; name: sched_list
; in:   none
; out:  one "[task] id name state ticks" line per task on the log
; clobbers: caller-saved
; patchable: yes
sched_list:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [rel sched_tasks]
    xor r12d, r12d
.task:
    cmp qword [rbx + TASK_STATE], TASK_FREE
    je .next
    lea rdi, [rel sched_msg_task]
    call kputs
    mov edi, r12d
    call [rel jt_kput_dec]
    mov edi, ' '
    call kputc
    lea rdi, [rbx + TASK_NAME]
    call kputs
    lea rdi, [rel sched_msg_ready]
    cmp qword [rbx + TASK_STATE], TASK_READY
    je .state
    lea rdi, [rel sched_msg_dead]
.state:
    call kputs
    mov rdi, [rbx + TASK_TICKS]
    call [rel jt_kput_dec]
    mov edi, 10
    call kputc
.next:
    add rbx, TASK_SIZE
    inc r12d
    cmp r12d, MAX_TASKS
    jb .task
    add rsp, 8
    pop r12
    pop rbx
    ret

sched_msg_task  db "[task] ", 0
sched_msg_ready db " ready ", 0
sched_msg_dead  db " dead ", 0

section .bss
alignb 8
sched_tasks      resb TASK_SIZE * MAX_TASKS
sched_current    resd 1
sched_slice_left resd 1
sched_on         resb 1
section .text
