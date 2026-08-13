ARCH ?= amd64
XNU_SOURCE_DIR ?= build/xnu-source

BUILD_DEPS_DIR := build/xnu-build-deps
BUILD_DIR := build/$(ARCH)
XNU_STAMP := $(BUILD_DIR)/xnu-upstream-stamp.txt
ISO_ROOT := $(BUILD_DIR)/iso-root
XNU_BUILD_DIR := $(BUILD_DIR)/xnu-build
XNU_ARTIFACTS_DIR := $(XNU_BUILD_DIR)/artifacts
ISO := $(BUILD_DIR)/apple-xnu-kernel-$(ARCH).iso
EFI_DIR := $(BUILD_DIR)/efi
EFI_IMAGE_SIZE_KB := 131072
LIMINE_DIR := build/limine

ifeq ($(ARCH),amd64)
XNU_ARCH := X86_64
EFI_BOOT_NAME := BOOTX64.EFI
else ifeq ($(ARCH),arm64)
XNU_ARCH := ARM64
EFI_BOOT_NAME := BOOTAA64.EFI
else
$(error Unsupported ARCH '$(ARCH)'; use amd64 or arm64)
endif

.PHONY: all fetch-xnu verify-xnu fetch-limine install-build-deps build-xnu iso verify clean

all: build-xnu iso verify

fetch-xnu:
	sh scripts/fetch-xnu.sh "$(XNU_SOURCE_DIR)"

verify-xnu: fetch-xnu
	sh scripts/verify-xnu-source.sh "$(XNU_SOURCE_DIR)"

fetch-limine:
	sh scripts/fetch-limine.sh "$(LIMINE_DIR)"

install-build-deps:
	sh scripts/install-xnu-build-deps.sh "$(BUILD_DEPS_DIR)"

build-xnu: verify-xnu install-build-deps
	sh scripts/build-xnu-kernel.sh "$(ARCH)" "$(XNU_SOURCE_DIR)" "$(XNU_BUILD_DIR)"

iso: $(ISO)

$(BUILD_DIR):
	mkdir -p "$@"

$(XNU_STAMP): xnu-upstream.env | $(BUILD_DIR)
	. ./xnu-upstream.env; \
	printf 'repo=%s\nref=%s\ncommit=%s\narch=%s\nxnu_arch=%s\n' "$$XNU_REPO_URL" "$$XNU_REF" "$$XNU_COMMIT" '$(ARCH)' '$(XNU_ARCH)' > $@

$(ISO): build-xnu fetch-limine $(XNU_STAMP)
	rm -rf "$(ISO_ROOT)"
	mkdir -p "$(ISO_ROOT)/xnu-kernel" "$(ISO_ROOT)/boot" "$(ISO_ROOT)/EFI/BOOT" "$(BUILD_DIR)/efi"
	printf 'apple-xnu-kernel-%s\n' '$(ARCH)' > "$(ISO_ROOT)/BUILD-LABEL.txt"
	cp "$(XNU_STAMP)" "$(ISO_ROOT)/XNU-UPSTREAM.txt"
	. ./xnu-upstream.env; \
	printf 'repo=%s\nversion=%s\nbinary_url=%s\nsha256=%s\n' "$$LIMINE_REPO_URL" "$$LIMINE_VERSION" "$$LIMINE_BINARY_URL" "$$LIMINE_BINARY_SHA256" > "$(ISO_ROOT)/LIMINE-UPSTREAM.txt"
	cp limine.conf "$(ISO_ROOT)/limine.conf"
	mkdir -p "$(ISO_ROOT)/boot/limine" "$(ISO_ROOT)/limine"
	cp "$(ISO_ROOT)/limine.conf" "$(ISO_ROOT)/boot/limine/limine.conf"
	cp "$(ISO_ROOT)/limine.conf" "$(ISO_ROOT)/boot/limine.conf"
	cp "$(ISO_ROOT)/limine.conf" "$(ISO_ROOT)/limine/limine.conf"
	cp "$(ISO_ROOT)/limine.conf" "$(ISO_ROOT)/EFI/BOOT/limine.conf"
	tar -C "$(XNU_ARTIFACTS_DIR)" -cf - . | tar -C "$(ISO_ROOT)/xnu-kernel" -xf -
	sh scripts/install-bootloader-sys.sh "$(XNU_ARTIFACTS_DIR)" "$(ISO_ROOT)/boot/bootloader.sys"
	cp "$(LIMINE_DIR)/$(EFI_BOOT_NAME)" "$(EFI_DIR)/$(EFI_BOOT_NAME)"
	cp "$(EFI_DIR)/$(EFI_BOOT_NAME)" "$(ISO_ROOT)/EFI/BOOT/$(EFI_BOOT_NAME)"
	dd if=/dev/zero of="$(ISO_ROOT)/EFI/efiboot.img" bs=1024 count="$(EFI_IMAGE_SIZE_KB)" >/dev/null 2>&1
	mformat -i "$(ISO_ROOT)/EFI/efiboot.img" ::
	mmd -i "$(ISO_ROOT)/EFI/efiboot.img" ::/EFI ::/EFI/BOOT ::/boot ::/boot/limine ::/limine
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(EFI_DIR)/$(EFI_BOOT_NAME)" "::/EFI/BOOT/$(EFI_BOOT_NAME)"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/limine.conf" "::/limine.conf"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/limine.conf" "::/EFI/BOOT/limine.conf"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/limine.conf" "::/boot/limine/limine.conf"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/limine.conf" "::/boot/limine.conf"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/limine.conf" "::/limine/limine.conf"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/boot/bootloader.sys" "::/boot/bootloader.sys"
	xorriso -as mkisofs -quiet -J -R -V APPLE_XNU_$(ARCH) -eltorito-alt-boot -e EFI/efiboot.img -no-emul-boot -o "$@" "$(ISO_ROOT)"

verify: $(ISO)
	test -s "$(ISO)"
	file "$(ISO)"
	isoinfo -R -f -i "$(ISO)" | tee "$(BUILD_DIR)/iso-contents.txt"
	xorriso -indev "$(ISO)" -report_el_torito plain 2>/dev/null | tee "$(BUILD_DIR)/iso-eltorito.txt"
	grep -q '/BUILD-LABEL.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/XNU-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/LIMINE-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/limine.conf' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/boot/limine/limine.conf' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/boot/limine.conf' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/limine/limine.conf' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/BOOT/limine.conf' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/boot/bootloader.sys' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/BOOT/$(EFI_BOOT_NAME)' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/efiboot.img' "$(BUILD_DIR)/iso-contents.txt"
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" ::/limine.conf | grep -q '/OS8'
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" ::/EFI/BOOT/limine.conf | grep -q '/OS8'
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" ::/boot/limine/limine.conf | grep -q '/OS8'
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" ::/boot/limine.conf | grep -q '/OS8'
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" ::/limine/limine.conf | grep -q '/OS8'
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/BOOT/$(EFI_BOOT_NAME)" >/dev/null
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/boot/bootloader.sys" >/dev/null
	grep -q '/xnu-kernel/xnu-kernel-artifacts.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -Eq '/xnu-kernel/.*/kernel(\.[^/]*)?$$|/xnu-kernel/.*/mach(\.[^/]*)?$$' "$(BUILD_DIR)/iso-contents.txt"
	grep -Ei 'EFI|UEFI' "$(BUILD_DIR)/iso-eltorito.txt"

clean:
	rm -rf build
