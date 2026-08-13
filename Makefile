ARCH ?= amd64

BUILD_DIR := build/$(ARCH)
ISO_ROOT := $(BUILD_DIR)/iso-root
KERNEL := $(BUILD_DIR)/xnu-basic-$(ARCH).elf
ISO := $(BUILD_DIR)/xnu-basic-$(ARCH).iso

COMMON_CFLAGS := -std=c11 -Wall -Wextra -O2 -ffreestanding -fno-stack-protector -fno-pic -nostdlib -Iinclude
ifeq ($(ARCH),amd64)
TARGET := x86_64-unknown-elf
ARCH_CFLAGS := -mno-red-zone -DARCH_AMD64
BOOT := src/boot_amd64.S
ISO_MODE := grub
LD_EMULATION := elf_x86_64
else ifeq ($(ARCH),arm64)
TARGET := aarch64-none-elf
ARCH_CFLAGS := -DARCH_ARM64
BOOT := src/boot_arm64.S
ISO_MODE := plain
LD_EMULATION := aarch64elf
else
$(error Unsupported ARCH '$(ARCH)'; use amd64 or arm64)
endif

CC := clang
LD := ld.lld

.PHONY: all kernel iso verify clean

all: iso verify

kernel: $(KERNEL)

iso: $(ISO)

$(BUILD_DIR):
	mkdir -p $@

$(KERNEL): src/kernel.c $(BOOT) linker/$(ARCH).ld | $(BUILD_DIR)
	$(CC) --target=$(TARGET) $(COMMON_CFLAGS) $(ARCH_CFLAGS) -c src/kernel.c -o $(BUILD_DIR)/kernel.o
	$(CC) --target=$(TARGET) $(COMMON_CFLAGS) $(ARCH_CFLAGS) -c $(BOOT) -o $(BUILD_DIR)/boot.o
	$(LD) -m $(LD_EMULATION) --build-id=none -T linker/$(ARCH).ld $(BUILD_DIR)/boot.o $(BUILD_DIR)/kernel.o -o $@

$(ISO): $(KERNEL)
	rm -rf $(ISO_ROOT)
	mkdir -p $(ISO_ROOT)/boot
	cp $(KERNEL) $(ISO_ROOT)/boot/xnu-basic-$(ARCH).elf
	printf 'xnu-basic-%s\n' '$(ARCH)' > $(ISO_ROOT)/BUILD-LABEL.txt
	if [ "$(ISO_MODE)" = "grub" ]; then \
		mkdir -p $(ISO_ROOT)/boot/grub; \
		sed 's/@ARCH@/$(ARCH)/g' iso/grub.cfg > $(ISO_ROOT)/boot/grub/grub.cfg; \
		grub-mkrescue -o $@ $(ISO_ROOT); \
	else \
		xorriso -as mkisofs -quiet -J -R -V XNU_BASIC_$(ARCH) -o $@ $(ISO_ROOT); \
	fi

verify: $(ISO)
	test -s $(KERNEL)
	test -s $(ISO)
	file $(KERNEL)
	file $(ISO)
	xorriso -indev $(ISO) -find / -type f -print | tee $(BUILD_DIR)/iso-contents.txt
	grep -q '/boot/xnu-basic-$(ARCH).elf' $(BUILD_DIR)/iso-contents.txt
	grep -q '/BUILD-LABEL.txt' $(BUILD_DIR)/iso-contents.txt

clean:
	rm -rf build
