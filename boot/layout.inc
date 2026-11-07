; Physical memory and disk layout shared by boot and kernel.

; disk (LBA)
STAGE2_LBA       equ 1
STAGE2_SECTORS   equ 32
KERNEL_LBA       equ 64
SRC_LBA          equ 2048                 ; source area, see tools/gensrc.asm
SRC_SECTORS      equ 2048

; low memory
BOOTINFO         equ 0x5000
BOOTINFO_E820_COUNT equ BOOTINFO + 0x00   ; word
BOOTINFO_FB_ADDR equ BOOTINFO + 0x08      ; qword, 0 = no framebuffer
BOOTINFO_FB_PITCH equ BOOTINFO + 0x10     ; dword, bytes per line
BOOTINFO_FB_WIDTH equ BOOTINFO + 0x14     ; dword
BOOTINFO_FB_HEIGHT equ BOOTINFO + 0x18    ; dword
BOOTINFO_FB_BPP  equ BOOTINFO + 0x1c      ; dword
BOOTINFO_E820    equ BOOTINFO + 0x100     ; 24-byte entries
BOOTINFO_E820_MAX equ 64
VBE_INFO_BUF     equ 0x6000               ; 512-byte VBE controller info
VBE_MODE_BUF     equ 0x6200               ; 256-byte VBE mode info
STAGE2_ADDR      equ 0x8000
LOAD_BUF         equ 0x20000              ; real-mode bounce buffer for kernel load
LOAD_CHUNK       equ 64                   ; sectors per int 13h read
PAGING_BASE      equ 0x70000
PML4_ADDR        equ 0x70000
PDPT_ADDR        equ 0x71000
PD_ADDR          equ 0x72000              ; 4 page directories, 4 GiB identity map
PAGING_SIZE      equ 0x6000
KERNEL_STACK_TOP equ 0x90000

; kernel
KERNEL_PHYS      equ 0x100000
