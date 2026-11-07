; The stack walk behind pixel provenance. There are no frame pointers, so it
; searches the stack above the newest frame. A word counts as the next frame
; only when the instruction before it calls the function holding the frame
; below, directly or through one jump, so stale words left in the stack drop
; out. Calls through a register cannot be checked and are taken on trust.

PROV_SCAN equ 128                   ; stack words searched for frames

; name: prov_walk
; in:   rbx = the stack slot holding the newest frame, prov_tmp = a chain
;       record holding that frame
; out:  the older frames found above it added to prov_tmp
; clobbers: rax, rcx, rdx, rsi, rdi
prov_walk:
    push r12
    push r13
    push r14
    mov rdi, [rbx]
    call prov_function
    jc .ret
    mov r12, rax                    ; function holding the newest frame
    lea r13, [rbx + 8]
    lea r14, [rbx + PROV_SCAN * 8]
.word:
    cmp dword [rel prov_tmp + PROV_COUNT], PROV_DEPTH
    jae .ret
    cmp r13, r14
    jae .ret
    mov rdi, [r13]
    mov rsi, r12
    call prov_calls
    jc .next
    mov rdi, [r13]
    mov eax, [rel prov_tmp + PROV_COUNT]
    lea rcx, [rel prov_tmp + PROV_FRAMES]
    mov [rcx + rax * 8], rdi
    inc dword [rel prov_tmp + PROV_COUNT]
    call prov_function
    jc .ret
    mov r12, rax
.next:
    add r13, 8
    jmp .word
.ret:
    pop r14
    pop r13
    pop r12
    ret

; name: prov_calls
; in:   rdi = a stack word, rsi = start of the function holding the frame
;       below it
; out:  CF=0 if the word returns past a call to that function: a direct
;       call, or a call through the jump table, to it or to a stub that
;       jumps to it
; clobbers: rax, rcx, rdx
prov_calls:
    mov rax, rdi
    call prov_text
    jc .no
    cmp byte [rdi - 5], 0xe8
    jne .indirect
    movsxd rax, dword [rdi - 4]
    add rax, rdi
    jmp .target
.indirect:                          ; a stale word's operands point anywhere:
    cmp word [rdi - 6], 0x15ff      ; read through them only inside the image
    jne .register
    movsxd rax, dword [rdi - 4]
    add rax, rdi
    call prov_text
    jnc .slot
    lea rcx, [rel bss_end - 8]
    cmp rax, rcx
    ja .no
    lea rcx, [rel sym_table]
    cmp rax, rcx
    jb .no
.slot:
    mov rax, [rax]
.target:
    call prov_text
    jc .no
    cmp rax, rsi
    je .yes
    xor ecx, ecx                    ; a stub: a jump in its first bytes
.stub:
    cmp byte [rax + rcx], 0xe9
    jne .short
    movsxd rdx, dword [rax + rcx + 1]
    add rdx, rax
    lea rdx, [rdx + rcx + 5]
    cmp rdx, rsi
    je .yes
.short:
    cmp byte [rax + rcx], 0xeb
    jne .step
    movsx rdx, byte [rax + rcx + 1]
    add rdx, rax
    lea rdx, [rdx + rcx + 2]
    cmp rdx, rsi
    je .yes
.step:
    inc ecx
    cmp ecx, 16
    jb .stub
    jmp .no
.register:                          ; call reg, [reg] or [reg + disp8]: the
    cmp byte [rdi - 2], 0xff        ; target is unknown, so take it on trust
    jne .disp8
    movzx eax, byte [rdi - 1]
    mov ecx, eax
    and ecx, 0xf8
    cmp ecx, 0xd0
    je .yes
    cmp ecx, 0x10
    jne .disp8
    and eax, 7
    cmp eax, 4
    jb .yes
    cmp eax, 6
    jae .yes
.disp8:
    cmp byte [rdi - 3], 0xff
    jne .no
    movzx eax, byte [rdi - 2]
    mov ecx, eax
    and ecx, 0xf8
    cmp ecx, 0x50
    jne .no
    and eax, 7
    cmp eax, 4
    jne .yes
.no:
    stc
    ret
.yes:
    clc
    ret

; name: prov_text
; in:   rax = address
; out:  CF=1 unless it is in the kernel's functions, at least 16 bytes
;       before their end
; clobbers: none
prov_text:
    push rcx
    lea rcx, [rel sym_table]
    cmp rax, [rcx + SYM_ADDR]
    jb .out
    lea rcx, [rel sym_table + (SYM_COUNT - 1) * SYM_RECORD]
    push rax
    mov rax, [rcx + SYM_ADDR]
    add rax, [rcx + SYM_SIZE]
    sub rax, 16
    cmp [rsp], rax
    pop rax
    jae .out
    pop rcx
    clc
    ret
.out:
    pop rcx
    stc
    ret

; name: prov_function
; in:   rdi = code address
; out:  rax = start of the function holding it, rdx = its symbol record;
;       CF=1 if none does (a binary search: sym_table is in address order)
; clobbers: rax, rcx, rdx
prov_function:
    push rsi
    xor esi, esi                    ; first record not ruled out
    mov ecx, SYM_COUNT              ; one past the last
.split:
    cmp esi, ecx
    jae .none
    lea eax, [rsi + rcx]
    shr eax, 1
    mov edx, eax
    shl rdx, 6
    push rcx
    lea rcx, [rel sym_table]
    add rdx, rcx
    pop rcx
    cmp rdi, [rdx + SYM_ADDR]
    jb .lower
    push rdi
    sub rdi, [rdx + SYM_ADDR]
    cmp rdi, [rdx + SYM_SIZE]
    pop rdi
    jb .found
    lea esi, [rax + 1]
    jmp .split
.lower:
    mov ecx, eax
    jmp .split
.found:
    mov rax, [rdx + SYM_ADDR]
    pop rsi
    clc
    ret
.none:
    pop rsi
    stc
    ret
