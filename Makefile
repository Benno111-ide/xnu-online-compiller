ARCH ?= amd64
XNU_SOURCE_DIR ?= build/xnu-source
XNU_KERNEL_ARTIFACT ?=
XNU_EFI_LOADER ?=

QEMU_MENU_WAIT ?= 14
QEMU_BOOT_DUMPS ?= 1
QEMU_BOOT_DUMP_INTERVAL ?= 5
ISO_PATH ?= $(ISO)
QEMU_RUN_SECONDS ?= 60

BUILD_DEPS_DIR := build/xnu-build-deps
BUILD_DIR := build/$(ARCH)
XNU_STAMP := $(BUILD_DIR)/xnu-upstream-stamp.txt
ISO_ROOT := $(BUILD_DIR)/iso-root
XNU_BUILD_DIR := $(BUILD_DIR)/xnu-build
XNU_ARTIFACTS_DIR := $(XNU_BUILD_DIR)/artifacts
ISO := $(BUILD_DIR)/apple-xnu-kernel-$(ARCH).iso
EFI_DIR := $(BUILD_DIR)/efi
EFI_IMAGE_SIZE_KB := 131072

ifeq ($(ARCH),amd64)
XNU_ARCH := X86_64
EFI_BOOT_NAME := BOOTX64.EFI
QEMU_BOOT_WAIT ?= 18
else ifeq ($(ARCH),arm64)
XNU_ARCH := ARM64
EFI_BOOT_NAME := BOOTAA64.EFI
QEMU_BOOT_WAIT ?= 34
else
$(error Unsupported ARCH '$(ARCH)'; use amd64 or arm64)
endif

ifneq ($(strip $(XNU_EFI_LOADER)),)
ISO_LOADER_PREREQ := $(XNU_EFI_LOADER)
endif

ifneq ($(strip $(XNU_KERNEL_ARTIFACT)),)
ISO_PREREQS := require-xnu-efi-loader $(ISO_LOADER_PREREQ) $(XNU_STAMP)
else
ISO_PREREQS := require-xnu-efi-loader $(ISO_LOADER_PREREQ) build-xnu $(XNU_STAMP)
endif

.PHONY: all fetch-xnu verify-xnu fetch-limine install-build-deps build-xnu build-bootstub require-xnu-efi-loader iso verify smoke-boot smoke-boot-capture virtualize-iso handoff-boot clean

all: iso verify

fetch-xnu:
	sh scripts/fetch-xnu.sh "$(XNU_SOURCE_DIR)"

verify-xnu: fetch-xnu
	sh scripts/verify-xnu-source.sh "$(XNU_SOURCE_DIR)"

fetch-limine:
	@echo "Limine is disabled; provide XNU_EFI_LOADER=/path/to/$(EFI_BOOT_NAME) for ISO builds."

install-build-deps:
	sh scripts/install-xnu-build-deps.sh "$(BUILD_DEPS_DIR)"

build-xnu: verify-xnu install-build-deps
	sh scripts/build-xnu-kernel.sh "$(ARCH)" "$(XNU_SOURCE_DIR)" "$(XNU_BUILD_DIR)"

build-bootstub:
	@echo "Limine bootstub is disabled; use XNU_EFI_LOADER=/path/to/$(EFI_BOOT_NAME)."
	@exit 1

require-xnu-efi-loader:
	@if [ -z "$(strip $(XNU_EFI_LOADER))" ]; then \
		echo "XNU_EFI_LOADER is required because the Limine bootstub is disabled." >&2; \
		echo "Provide a real XNU/Darwin EFI loader, for example:" >&2; \
		echo "  make ARCH=$(ARCH) XNU_EFI_LOADER=/path/to/$(EFI_BOOT_NAME) iso" >&2; \
		echo "Apple's open XNU source does not include boot.efi/iBoot, so this repo cannot synthesize that file." >&2; \
		exit 2; \
	fi

iso: $(ISO)

$(BUILD_DIR):
	mkdir -p "$@"

$(XNU_STAMP): xnu-upstream.env | $(BUILD_DIR)
	. ./xnu-upstream.env; \
	printf 'repo=%s\nref=%s\ncommit=%s\narch=%s\nxnu_arch=%s\n' "$$XNU_REPO_URL" "$$XNU_REF" "$$XNU_COMMIT" '$(ARCH)' '$(XNU_ARCH)' > $@

$(ISO): $(ISO_PREREQS)
	rm -rf "$(ISO_ROOT)"
	mkdir -p "$(ISO_ROOT)/xnu-kernel" "$(ISO_ROOT)/boot" "$(ISO_ROOT)/EFI/BOOT" "$(BUILD_DIR)/efi"
	printf 'apple-xnu-kernel-%s\n' '$(ARCH)' > "$(ISO_ROOT)/BUILD-LABEL.txt"
	cp "$(XNU_STAMP)" "$(ISO_ROOT)/XNU-UPSTREAM.txt"
	if [ -n "$(XNU_KERNEL_ARTIFACT)" ]; then \
		test -s "$(XNU_KERNEL_ARTIFACT)"; \
		xnu_validation=$$(python3 scripts/validate-xnu-macho.py "$(ARCH)" "$(XNU_KERNEL_ARTIFACT)") || exit 1; \
		printf '%s\n' "$$xnu_validation" | tee "$(ISO_ROOT)/xnu-kernel/xnu-kernel-validation.txt"; \
		mkdir -p "$(ISO_ROOT)/xnu-kernel/external"; \
		xnu_kernel_artifact="$(XNU_KERNEL_ARTIFACT)"; \
		xnu_kernel_name=$$(basename "$$xnu_kernel_artifact"); \
		cp "$$xnu_kernel_artifact" "$(ISO_ROOT)/xnu-kernel/external/$$xnu_kernel_name"; \
		printf '%s\n' "external/$$xnu_kernel_name" > "$(ISO_ROOT)/xnu-kernel/xnu-kernel-artifacts.txt"; \
	else \
		tar -C "$(XNU_ARTIFACTS_DIR)" -cf - . | tar -C "$(ISO_ROOT)/xnu-kernel" -xf -; \
		xnu_kernel_artifact=; \
		xnu_validation=; \
		for candidate in $$(find "$(XNU_ARTIFACTS_DIR)" -type f \( -name 'kernel*' -o -name 'mach*' \) | sort); do \
			xnu_validation=$$(python3 scripts/validate-xnu-macho.py "$(ARCH)" "$$candidate" 2>/dev/null) || continue; \
			xnu_kernel_artifact="$$candidate"; \
			break; \
		done; \
		test -n "$$xnu_kernel_artifact"; \
		printf '%s\n' "$$xnu_validation" | tee "$(ISO_ROOT)/xnu-kernel/xnu-kernel-validation.txt"; \
	fi; \
	cp "$$xnu_kernel_artifact" "$(ISO_ROOT)/boot/xnu-kernel.macho"
	cp "$(XNU_EFI_LOADER)" "$(EFI_DIR)/$(EFI_BOOT_NAME)"
	cp "$(EFI_DIR)/$(EFI_BOOT_NAME)" "$(ISO_ROOT)/EFI/BOOT/$(EFI_BOOT_NAME)"
	if command -v truncate >/dev/null 2>&1; then \
		truncate -s "$$(($(EFI_IMAGE_SIZE_KB) * 1024))" "$(ISO_ROOT)/EFI/efiboot.img"; \
	else \
		dd if=/dev/zero of="$(ISO_ROOT)/EFI/efiboot.img" bs=1024 count="$(EFI_IMAGE_SIZE_KB)" >/dev/null 2>&1; \
	fi
	mformat -i "$(ISO_ROOT)/EFI/efiboot.img" ::
	mmd -i "$(ISO_ROOT)/EFI/efiboot.img" ::/EFI ::/EFI/BOOT ::/boot
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(EFI_DIR)/$(EFI_BOOT_NAME)" "::/EFI/BOOT/$(EFI_BOOT_NAME)"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/boot/xnu-kernel.macho" "::/boot/xnu-kernel.macho"
	xorriso -as mkisofs -quiet -J -R -V APPLE_XNU_$(ARCH) -eltorito-alt-boot -e EFI/efiboot.img -no-emul-boot -o "$@" "$(ISO_ROOT)"

verify: $(ISO)
	test -s "$(ISO)"
	file "$(ISO)"
	if command -v isoinfo >/dev/null 2>&1; then \
		isoinfo -R -f -i "$(ISO)"; \
	else \
		xorriso -indev "$(ISO)" -find / -exec lsdl 2>/dev/null; \
	fi | tee "$(BUILD_DIR)/iso-contents.txt"
	xorriso -indev "$(ISO)" -report_el_torito plain 2>/dev/null | tee "$(BUILD_DIR)/iso-eltorito.txt"
	grep -q '/BUILD-LABEL.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/XNU-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/boot/xnu-kernel.macho' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-kernel/xnu-kernel-validation.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/BOOT/$(EFI_BOOT_NAME)' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/efiboot.img' "$(BUILD_DIR)/iso-contents.txt"
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/BOOT/$(EFI_BOOT_NAME)" >/dev/null
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/boot/xnu-kernel.macho" >/dev/null
	grep -q '/xnu-kernel/xnu-kernel-artifacts.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q 'arch=$(ARCH)' "$(ISO_ROOT)/xnu-kernel/xnu-kernel-validation.txt"
	grep -q 'entry=0x' "$(ISO_ROOT)/xnu-kernel/xnu-kernel-validation.txt"
	test -s "$(ISO_ROOT)/xnu-kernel/xnu-kernel-artifacts.txt"
	grep -Ei 'EFI|UEFI' "$(BUILD_DIR)/iso-eltorito.txt"

smoke-boot:
	test -s "$(ISO)"
	test -s "$(ISO_ROOT)/EFI/efiboot.img"
	QEMU_ALLOW_ANY_BOOT=1 QEMU_MENU_WAIT="$(QEMU_MENU_WAIT)" QEMU_BOOT_WAIT="$(QEMU_BOOT_WAIT)" QEMU_BOOT_DUMPS="$(QEMU_BOOT_DUMPS)" QEMU_BOOT_DUMP_INTERVAL="$(QEMU_BOOT_DUMP_INTERVAL)" sh scripts/smoke-boot-efi.sh "$(ARCH)" "$(ISO_ROOT)/EFI/efiboot.img" "$(BUILD_DIR)/efi-smoke"

smoke-boot-capture:
	test -s "$(ISO)"
	test -s "$(ISO_ROOT)/EFI/efiboot.img"
	QEMU_ALLOW_ANY_BOOT=1 QEMU_MENU_WAIT="$(QEMU_MENU_WAIT)" QEMU_BOOT_WAIT="$(QEMU_BOOT_WAIT)" QEMU_BOOT_DUMPS="$(QEMU_BOOT_DUMPS)" QEMU_BOOT_DUMP_INTERVAL="$(QEMU_BOOT_DUMP_INTERVAL)" sh scripts/smoke-boot-efi.sh "$(ARCH)" "$(ISO_ROOT)/EFI/efiboot.img" "$(BUILD_DIR)/efi-smoke"

virtualize-iso:
	test -s "$(ISO_PATH)"
	QEMU_RUN_SECONDS="$(QEMU_RUN_SECONDS)" sh scripts/virtualize-iso-capture.sh "$(ARCH)" "$(ISO_PATH)" "$(BUILD_DIR)/iso-virtualize"

handoff-boot:
	@echo "Limine handoff boot is disabled; use iso/smoke-boot with XNU_EFI_LOADER."
	@exit 1

clean:
	rm -rf build
