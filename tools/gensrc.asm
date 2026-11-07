; Source area and symbol table for tools/gen.asm: build/gen/src.bin and
; build/gen/symtab.inc.

SYS_GETDENTS64 equ 217
DENTS_SIZE equ 1 << 16
AREA_SIZE  equ 1 << 23

SRC_DIR       equ 16                ; as in forge/source.asm
SRC_DIR_ENTRY equ 48
SRC_FILES_MAX equ 64
SRC_NAME_MAX  equ 31
SRC_FILE      equ 2

; gen_src: both files written
gen_src:
    call build_src
    call gen_sym
    lea rdi, [path_src]
    lea rsi, [area]
    mov rdx, [area_len]
    jmp write_if_changed

; build_src: the source area in `area`: a header, a directory of
; SRC_FILES_MAX entries, then the files' text back to back, first every
; file holding a patchable function, then the user files in files/, each
; group sorted by name
build_src:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor ebx, ebx
.module:
    cmp rbx, [funcs_n]
    jae .modules_done
    lea rax, [func_patch]
    cmp byte [rax + rbx], 0
    je .next_func
    lea rax, [func_file]
    mov rax, [rax + rbx * 8]
    lea rcx, [file_path]
    mov rdi, [rcx + rax * 8]
    xor r12d, r12d
.known:
    cmp r12, [ents_n]
    jae .add_module
    lea rax, [ent_path]
    mov rsi, [rax + r12 * 8]
    push rdi
    call streq
    pop rdi
    je .next_func
    inc r12
    jmp .known
.add_module:
    xor esi, esi
    call add_entry
.next_func:
    inc rbx
    jmp .module
.modules_done:
    xor edi, edi
    mov rsi, [ents_n]
    call sort_entries
    mov r15, [ents_n]               ; first user file
    lea rdi, [dir_files]
    mov esi, 0x10000                ; O_DIRECTORY
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .no_files
    mov r12, rax
.dents:
    mov rdi, r12
    lea rsi, [dents]
    mov edx, DENTS_SIZE
    mov eax, SYS_GETDENTS64
    syscall
    test rax, rax
    jle .dents_done
    lea r13, [dents]
    lea r14, [dents + rax]
.dent:
    cmp r13, r14
    jae .dents
    lea rdi, [r13 + 19]             ; d_name
    cmp word [rdi], "."
    je .skip_dent
    cmp word [rdi], ".."
    jne .user
    cmp byte [rdi + 2], 0
    je .skip_dent
.user:
    mov rsi, rdi
    mov rdi, [arena_ptr]
    mov rbx, rdi
    mov dword [rdi], "file"
    mov word [rdi + 4], "s/"
    add rdi, 6
.copy:
    lodsb
    stosb
    test al, al
    jnz .copy
    mov [arena_ptr], rdi
    mov rdi, rbx
    mov esi, SRC_FILE
    call add_entry
.skip_dent:
    movzx eax, word [r13 + 16]      ; d_reclen
    add r13, rax
    jmp .dent
.dents_done:
    mov rdi, r12
    mov eax, SYS_CLOSE
    syscall
    mov rdi, r15
    mov rsi, [ents_n]
    call sort_entries
.no_files:
    mov r12d, SRC_DIR + SRC_DIR_ENTRY * SRC_FILES_MAX
    xor ebx, ebx
.entry:
    cmp rbx, [ents_n]
    jae .header
    lea rax, [ent_path]
    mov rdi, [rax + rbx * 8]
    lea rax, [ent_flags]
    cmp qword [rax + rbx * 8], 0
    je .named
    add rdi, 6                      ; a user file is named without files/
.named:
    mov rsi, rdi
    imul rdi, rbx, SRC_DIR_ENTRY
    lea r13, [area + SRC_DIR + rdi]
    mov rdi, r13
    mov ecx, SRC_NAME_MAX + 1
.name:
    lodsb
    stosb
    test al, al
    jz .name_done
    loop .name
    jmp fail_name
.name_done:
    lea rax, [ent_path]
    mov rdi, [rax + rbx * 8]
    call load_file
    lea rcx, [ent_start]
    mov [rcx + rbx * 8], r12
    mov [r13 + 32], r12d
    mov [r13 + 36], edx
    lea rcx, [ent_flags]
    mov rcx, [rcx + rbx * 8]
    mov [r13 + 40], rcx
    lea rdi, [area + r12]
    lea rcx, [r12 + rdx]
    cmp rcx, AREA_SIZE
    ja fail_full
    mov rsi, rax
    mov rcx, rdx
    add r12, rdx
    rep movsb
    inc rbx
    jmp .entry
.header:
    mov dword [area], "VSRC"
    mov rax, [ents_n]
    mov [area + 4], eax
    mov [area + 8], r12d
    mov [area_len], r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; add_entry(rdi = path, rsi = flags): a file of the source area
add_entry:
    mov rax, [ents_n]
    cmp rax, SRC_FILES_MAX
    jae fail_full
    lea rcx, [ent_path]
    mov [rcx + rax * 8], rdi
    lea rcx, [ent_flags]
    mov [rcx + rax * 8], rsi
    inc qword [ents_n]
    ret

; sort_entries(rdi = first, rsi = end): those entries sorted by path, all
; with the same flags
sort_entries:
    push rbx
    push r12
    push r13
    mov r12, rsi
    lea rbx, [rdi + 1]
.outer:
    cmp rbx, r12
    jae .done
    mov r13, rbx
.inner:
    cmp r13, rdi
    jbe .next
    lea rax, [ent_path]
    push rdi
    mov rdi, [rax + r13 * 8 - 8]
    mov rsi, [rax + r13 * 8]
    call streq
    pop rdi
    jbe .next
    lea rax, [ent_path]
    mov rcx, [rax + r13 * 8 - 8]
    mov rdx, [rax + r13 * 8]
    mov [rax + r13 * 8 - 8], rdx
    mov [rax + r13 * 8], rcx
    dec r13
    jmp .inner
.next:
    inc rbx
    jmp .outer
.done:
    pop r13
    pop r12
    pop rbx
    ret

; gen_sym: build/gen/symtab.inc, a record per function in image order
gen_sym:
    push rbx
    push r12
    push r13
    call out_reset
    lea rdi, [sym_head]
    call out_s
    xor ebx, ebx
    xor r12d, r12d                  ; jump table slot
.func:
    cmp rbx, [funcs_n]
    jae .end
    lea rax, [func_len]
    cmp qword [rax + rbx * 8], SRC_NAME_MAX
    ja fail_name
    lea rdi, [s_sym_dq]
    call out_s
    mov rdi, rbx
    call out_func
    lea rdi, [s_comma]
    call out_s
    lea rax, [rbx + 1]
    cmp rax, [funcs_n]
    jae .last
    mov rdi, rax
    call out_func
    jmp .size
.last:
    lea rdi, [s_end_magic]
    call out_s
.size:
    lea rdi, [s_minus]
    call out_s
    mov rdi, rbx
    call out_func
    lea rdi, [s_sym_dd]
    call out_s
    or r13, -1
    lea rax, [func_patch]
    cmp byte [rax + rbx], 0
    je .slot
    mov r13, r12
    inc r12
.slot:
    mov rdi, r13
    call out_dec
    lea rdi, [s_comma]
    call out_s
    mov rdi, rbx
    call src_offset
    mov rdi, rax
    call out_dec
    lea rdi, [s_sym_zeros]
    call out_s
    mov rdi, rbx
    call out_func
    lea rdi, [s_sym_times]
    call out_s
    lea rax, [func_len]
    mov rdi, [rax + rbx * 8]
    call out_dec
    lea rdi, [s_sym_pad]
    call out_s
    inc rbx
    jmp .func
.end:
    lea rdi, [s_sym_count]
    call out_s
    mov rdi, [funcs_n]
    call out_dec
    mov edi, 10
    call out_c
    lea rdi, [path_sym]
    call out_write
    pop r13
    pop r12
    pop rbx
    ret

; src_offset(rdi = function index): rax = offset of its header in the
; source area, -1 if its file is not there
src_offset:
    push rbx
    push r12
    lea rax, [func_off]
    mov r12, [rax + rdi * 8]
    lea rax, [func_file]
    mov rax, [rax + rdi * 8]
    lea rcx, [file_path]
    mov rdi, [rcx + rax * 8]
    xor ebx, ebx
.entry:
    cmp rbx, [ents_n]
    jae .none
    lea rax, [ent_path]
    mov rsi, [rax + rbx * 8]
    push rdi
    call streq
    pop rdi
    je .found
    inc rbx
    jmp .entry
.found:
    lea rax, [ent_start]
    mov rax, [rax + rbx * 8]
    add rax, r12
    jmp .ret
.none:
    or rax, -1
.ret:
    pop r12
    pop rbx
    ret

fail_name:
    lea rdi, [msg_name]
    call err_s
    jmp fail


section .data
path_sym       db "build/gen/symtab.inc", 0
path_src      db "build/gen/src.bin", 0
dir_files      db "files", 0
msg_name       db "gen: a name is longer than 31 characters", 10, 0
sym_head       db "; generated by tools/gen.asm: one 64-byte record per function, in image order", 10
               db "; +0 address, +8 size, +16 jump table slot (-1 if none),", 10
               db "; +20 offset of its header in the source area (-1 if not embedded), +32 name", 10
               db "align 8", 10, "sym_table:", 10, 0
s_sym_dq       db "    dq ", 0
s_comma        db ", ", 0
s_end_magic    db "kernel_end_magic", 0
s_minus        db " - ", 0
s_sym_dd       db 10, "    dd ", 0
s_sym_zeros    db ", 0, 0", 10, '    db "', 0
s_sym_times    db '"', 10, "    times 32 - ", 0
s_sym_pad      db " db 0", 10, 0
s_sym_count    db "SYM_COUNT equ ", 0

section .bss

alignb 8
alignb 8
ents_n       resq 1
ent_path     resq SRC_FILES_MAX
ent_flags    resq SRC_FILES_MAX
ent_start    resq SRC_FILES_MAX
area_len     resq 1
dents        resb DENTS_SIZE
area         resb AREA_SIZE
section .text
