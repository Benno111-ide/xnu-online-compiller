ARCH ?= amd64
XNU_SOURCE_DIR ?= build/xnu-source
XNU_KERNEL_ARTIFACT ?=
XNU_EFI_LOADER ?=
XNU_BOOT_ARGS ?= -v keepsyms=1 debug=0x144 serial=3

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
BUILTIN_XNU_EFI_LOADER = $(EFI_DIR)/builtin/$(EFI_BOOT_NAME)
EFI_IMAGE_SIZE_KB := 131072
OPENCORE_DIR := build/opencore

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
ISO_LOADER := $(XNU_EFI_LOADER)
ISO_LOADER_PREREQ := $(XNU_EFI_LOADER)
ISO_EFI_VENDOR := external
else
ifeq ($(ARCH),amd64)
ISO_LOADER := $(OPENCORE_DIR)/X64/EFI/BOOT/BOOTx64.efi
ISO_LOADER_PREREQ := fetch-opencore
ISO_EFI_VENDOR := opencore
else
ISO_LOADER := $(BUILTIN_XNU_EFI_LOADER)
ISO_LOADER_PREREQ := build-xnu-efi-loader
ISO_EFI_VENDOR := fallback
endif
endif

ifneq ($(strip $(XNU_KERNEL_ARTIFACT)),)
ISO_PREREQS := $(ISO_LOADER_PREREQ) $(XNU_STAMP)
else
ISO_PREREQS := $(ISO_LOADER_PREREQ) build-xnu $(XNU_STAMP)
endif

.PHONY: all fetch-xnu verify-xnu fetch-limine fetch-opencore install-build-deps build-xnu build-bootstub build-xnu-efi-loader iso verify smoke-boot smoke-boot-capture virtualize-iso handoff-boot clean

all: iso verify

fetch-xnu:
	sh scripts/fetch-xnu.sh "$(XNU_SOURCE_DIR)"

verify-xnu: fetch-xnu
	sh scripts/verify-xnu-source.sh "$(XNU_SOURCE_DIR)"

fetch-limine:
	@echo "Limine is disabled; provide XNU_EFI_LOADER=/path/to/$(EFI_BOOT_NAME) for ISO builds."

fetch-opencore:
	XNU_BOOT_ARGS="$(XNU_BOOT_ARGS)" sh scripts/fetch-opencore.sh "$(OPENCORE_DIR)"

install-build-deps:
	sh scripts/install-xnu-build-deps.sh "$(BUILD_DEPS_DIR)"

build-xnu: verify-xnu install-build-deps
	sh scripts/build-xnu-kernel.sh "$(ARCH)" "$(XNU_SOURCE_DIR)" "$(XNU_BUILD_DIR)"

build-bootstub:
	@echo "Limine bootstub is disabled; use XNU_EFI_LOADER=/path/to/$(EFI_BOOT_NAME)."
	@exit 1

build-xnu-efi-loader:
	XNU_BOOT_ARGS="$(XNU_BOOT_ARGS)" sh scripts/build-xnu-efi-loader.sh "$(ARCH)" "$(BUILD_DIR)/xnu-efi-loader" "$(BUILTIN_XNU_EFI_LOADER)"

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
	printf '%s\n' "$(XNU_BOOT_ARGS)" > "$(ISO_ROOT)/BOOT-ARGS.txt"
	cp "$(XNU_STAMP)" "$(ISO_ROOT)/XNU-UPSTREAM.txt"
	. ./xnu-upstream.env; \
	printf 'efi_vendor=%s\nopencore_repo=%s\nopencore_version=%s\nopencore_binary_url=%s\n' '$(ISO_EFI_VENDOR)' "$$OPENCORE_REPO_URL" "$$OPENCORE_VERSION" "$$OPENCORE_BINARY_URL" > "$(ISO_ROOT)/EFI-UPSTREAM.txt"
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
	cp "$(ISO_LOADER)" "$(EFI_DIR)/$(EFI_BOOT_NAME)"
	cp "$(EFI_DIR)/$(EFI_BOOT_NAME)" "$(ISO_ROOT)/EFI/BOOT/$(EFI_BOOT_NAME)"
	if [ "$(ISO_EFI_VENDOR)" = "opencore" ]; then \
		mkdir -p "$(ISO_ROOT)/EFI/OC"; \
		tar -C "$(OPENCORE_DIR)/X64/EFI/OC" -cf - . | tar -C "$(ISO_ROOT)/EFI/OC" -xf -; \
	fi
	if command -v truncate >/dev/null 2>&1; then \
		truncate -s "$$(($(EFI_IMAGE_SIZE_KB) * 1024))" "$(ISO_ROOT)/EFI/efiboot.img"; \
	else \
		dd if=/dev/zero of="$(ISO_ROOT)/EFI/efiboot.img" bs=1024 count="$(EFI_IMAGE_SIZE_KB)" >/dev/null 2>&1; \
	fi
	mformat -i "$(ISO_ROOT)/EFI/efiboot.img" ::
	mmd -i "$(ISO_ROOT)/EFI/efiboot.img" ::/EFI ::/EFI/BOOT ::/boot
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(EFI_DIR)/$(EFI_BOOT_NAME)" "::/EFI/BOOT/$(EFI_BOOT_NAME)"
	mcopy -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/BOOT-ARGS.txt" "::/BOOT-ARGS.txt"
	if [ "$(ISO_EFI_VENDOR)" = "opencore" ]; then \
		mmd -i "$(ISO_ROOT)/EFI/efiboot.img" ::/EFI/OC; \
		mcopy -s -i "$(ISO_ROOT)/EFI/efiboot.img" "$(ISO_ROOT)/EFI/OC"/* "::/EFI/OC/"; \
	fi
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
	grep -q '/BOOT-ARGS.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/XNU-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/boot/xnu-kernel.macho' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-kernel/xnu-kernel-validation.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/BOOT/$(EFI_BOOT_NAME)' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/EFI/efiboot.img' "$(BUILD_DIR)/iso-contents.txt"
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/BOOT/$(EFI_BOOT_NAME)" >/dev/null
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/BOOT-ARGS.txt" | grep -q -- "$(XNU_BOOT_ARGS)"
	mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/boot/xnu-kernel.macho" >/dev/null
	if [ "$(ISO_EFI_VENDOR)" = "opencore" ]; then \
		grep -q '/EFI/OC/OpenCore.efi' "$(BUILD_DIR)/iso-contents.txt"; \
		grep -q '/EFI/OC/config.plist' "$(BUILD_DIR)/iso-contents.txt"; \
		grep -q '/EFI/OC/Drivers/OpenRuntime.efi' "$(BUILD_DIR)/iso-contents.txt"; \
		grep -q '/EFI/OC/Drivers/OpenHfsPlus.efi' "$(BUILD_DIR)/iso-contents.txt"; \
		mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/OC/OpenCore.efi" >/dev/null; \
		mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/OC/config.plist" >/dev/null; \
		mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/OC/Drivers/OpenRuntime.efi" >/dev/null; \
		mtype -i "$(ISO_ROOT)/EFI/efiboot.img" "::/EFI/OC/Drivers/OpenHfsPlus.efi" >/dev/null; \
		python3 -c 'import plistlib,sys; p=plistlib.load(open(sys.argv[1],"rb")); s=p["Misc"]["Security"]; g=p["PlatformInfo"]["Generic"]; n=p["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]; assert s["Vault"] == "Optional"; assert s["SecureBootModel"] == "Disabled"; assert s["ScanPolicy"] == 0; assert g["SystemUUID"] != "00000000-0000-0000-0000-000000000000"; assert n["boot-args"] == sys.argv[2]; assert [d["Path"] for d in p["UEFI"]["Drivers"] if d.get("Enabled")] == ["OpenRuntime.efi", "OpenHfsPlus.efi"]' "$(ISO_ROOT)/EFI/OC/config.plist" "$(XNU_BOOT_ARGS)"; \
	fi
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
