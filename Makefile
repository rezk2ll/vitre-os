NASM  ?= nasm
PY    ?= python3
QEMU  ?= qemu-system-x86_64
BUILD := build
IMG   := $(BUILD)/vitre.img

QEMU_FLAGS := -machine pc -m 128M -drive file=$(IMG),format=raw,if=ide,index=0 \
              -serial stdio -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
              -nic user,model=e1000

.PHONY: all run debug test clean

all: $(IMG)

$(BUILD):
	mkdir -p $@

# NASM's -MD drops %include'd files when combined with -o, so the dependency
# list comes from a separate -M pass. It goes through a temp file: a failed
# pass would otherwise leave an empty .d and hide every include from make.
ASM = $(NASM) -f bin -I. -M -MP -MT $@ $< > $@.d.tmp && mv $@.d.tmp $@.d && $(NASM) -f bin -I.

layout = $(shell awk '$$1 == "$(1)" { print $$3 }' boot/layout.inc)

$(BUILD)/stage1.bin: boot/stage1.asm | $(BUILD)
	$(ASM) -o $@ $<

$(BUILD)/kernel.bin: kernel/main.asm | $(BUILD)
	$(ASM) -o $@ $<

$(BUILD)/stage2.bin: boot/stage2.asm $(BUILD)/kernel.bin | $(BUILD)
	$(ASM) -DKERNEL_SECTORS=$$(( ($$(stat -c %s $(BUILD)/kernel.bin) + 511) / 512 )) -o $@ $<

$(IMG): $(BUILD)/stage1.bin $(BUILD)/stage2.bin $(BUILD)/kernel.bin
	rm -f $@
	truncate -s 4M $@
	dd if=$(BUILD)/stage1.bin of=$@ conv=notrunc status=none
	dd if=$(BUILD)/stage2.bin of=$@ bs=512 seek=$(call layout,STAGE2_LBA) conv=notrunc status=none
	dd if=$(BUILD)/kernel.bin of=$@ bs=512 seek=$(call layout,KERNEL_LBA) conv=notrunc status=none

# the test harness reads text off screendumps with the same glyphs
$(BUILD)/font.bin: glass/font.asm | $(BUILD)
	$(ASM) -o $@ $<

-include $(wildcard $(BUILD)/*.d)

run: $(IMG)
	$(QEMU) $(QEMU_FLAGS)

# gdb: target remote :1234
debug: $(IMG)
	$(QEMU) $(QEMU_FLAGS) -s -S

test: $(IMG) $(BUILD)/font.bin
	$(PY) tests/run.py $(T)

clean:
	rm -rf $(BUILD)
