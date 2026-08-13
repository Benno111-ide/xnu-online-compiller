ARCH ?= amd64
XNU_SOURCE_DIR ?= build/xnu-source

BUILD_DIR := build/$(ARCH)
XNU_STAMP := $(BUILD_DIR)/xnu-upstream-stamp.txt
ISO_ROOT := $(BUILD_DIR)/iso-root
ISO := $(BUILD_DIR)/apple-xnu-source-$(ARCH).iso

ifeq ($(ARCH),amd64)
XNU_ARCH := X86_64
else ifeq ($(ARCH),arm64)
XNU_ARCH := ARM64
else
$(error Unsupported ARCH '$(ARCH)'; use amd64 or arm64)
endif

.PHONY: all fetch-xnu verify-xnu iso verify clean

all: verify-xnu iso verify

fetch-xnu:
	sh scripts/fetch-xnu.sh "$(XNU_SOURCE_DIR)"

verify-xnu: fetch-xnu
	sh scripts/verify-xnu-source.sh "$(XNU_SOURCE_DIR)"

iso: $(ISO)

$(BUILD_DIR):
	mkdir -p "$@"

$(XNU_STAMP): xnu-upstream.env | $(BUILD_DIR)
	. ./xnu-upstream.env; \
	printf 'repo=%s\nref=%s\ncommit=%s\narch=%s\nxnu_arch=%s\n' "$$XNU_REPO_URL" "$$XNU_REF" "$$XNU_COMMIT" '$(ARCH)' '$(XNU_ARCH)' > $@

$(ISO): verify-xnu $(XNU_STAMP)
	rm -rf "$(ISO_ROOT)"
	mkdir -p "$(ISO_ROOT)/xnu-source"
	printf 'apple-xnu-source-%s\n' '$(ARCH)' > "$(ISO_ROOT)/BUILD-LABEL.txt"
	cp "$(XNU_STAMP)" "$(ISO_ROOT)/XNU-UPSTREAM.txt"
	tar --exclude='.git' -C "$(XNU_SOURCE_DIR)" -cf - . | tar -C "$(ISO_ROOT)/xnu-source" -xf -
	xorriso -as mkisofs -quiet -J -R -V APPLE_XNU_$(ARCH) -o "$@" "$(ISO_ROOT)"

verify: $(ISO)
	test -s "$(ISO)"
	file "$(ISO)"
	isoinfo -R -f -i "$(ISO)" | tee "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/BUILD-LABEL.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/XNU-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-source/APPLE_LICENSE' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-source/README.md' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-source/Makefile' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-source/bsd/Makefile' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-source/osfmk/Makefile' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-source/iokit/Makefile' "$(BUILD_DIR)/iso-contents.txt"

clean:
	rm -rf build
