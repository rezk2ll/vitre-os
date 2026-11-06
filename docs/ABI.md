# ABI

- Arguments: `rdi, rsi, rdx, rcx, r8, r9`, in that order.
- Return: `rax`, plus `rdx` for a second value.
- Callee-saved: `rbx, rbp, r12, r13, r14, r15`. Everything else is caller-saved.
- Errors: carry flag set means failure, `rax` holds the error code.
- The stack is 16-byte aligned at every `call`.

Every function starts with a header:

```
; name: tcp_send
; in:   rdi = socket ptr, rsi = buf, rdx = len
; out:  rax = bytes queued, CF=1 on error
; clobbers: rcx, r8-r11
; patchable: yes
```

Names are `module_action` in snake_case, local labels start with `.`.
