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

$(BUILD)/stage1.bin: boot/stage1.asm | $(BUILD)
	$(NASM) -f bin -o $@ $<

$(IMG): $(BUILD)/stage1.bin
	cp $< $@
	truncate -s 1M $@

run: $(IMG)
	$(QEMU) $(QEMU_FLAGS)

# gdb: target remote :1234
debug: $(IMG)
	$(QEMU) $(QEMU_FLAGS) -s -S

test: $(IMG)
	$(PY) tests/run.py $(T)

clean:
	rm -rf $(BUILD)
