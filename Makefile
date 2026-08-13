ARCH ?= amd64
XNU_SOURCE_DIR ?= build/xnu-source

BUILD_DEPS_DIR := build/xnu-build-deps
BUILD_DIR := build/$(ARCH)
XNU_STAMP := $(BUILD_DIR)/xnu-upstream-stamp.txt
ISO_ROOT := $(BUILD_DIR)/iso-root
XNU_BUILD_DIR := $(BUILD_DIR)/xnu-build
XNU_ARTIFACTS_DIR := $(XNU_BUILD_DIR)/artifacts
ISO := $(BUILD_DIR)/apple-xnu-kernel-$(ARCH).iso

ifeq ($(ARCH),amd64)
XNU_ARCH := X86_64
else ifeq ($(ARCH),arm64)
XNU_ARCH := ARM64
else
$(error Unsupported ARCH '$(ARCH)'; use amd64 or arm64)
endif

.PHONY: all fetch-xnu verify-xnu install-build-deps build-xnu iso verify clean

all: build-xnu iso verify

fetch-xnu:
	sh scripts/fetch-xnu.sh "$(XNU_SOURCE_DIR)"

verify-xnu: fetch-xnu
	sh scripts/verify-xnu-source.sh "$(XNU_SOURCE_DIR)"

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

$(ISO): build-xnu $(XNU_STAMP)
	rm -rf "$(ISO_ROOT)"
	mkdir -p "$(ISO_ROOT)/xnu-kernel"
	printf 'apple-xnu-kernel-%s\n' '$(ARCH)' > "$(ISO_ROOT)/BUILD-LABEL.txt"
	cp "$(XNU_STAMP)" "$(ISO_ROOT)/XNU-UPSTREAM.txt"
	tar -C "$(XNU_ARTIFACTS_DIR)" -cf - . | tar -C "$(ISO_ROOT)/xnu-kernel" -xf -
	xorriso -as mkisofs -quiet -J -R -V APPLE_XNU_$(ARCH) -o "$@" "$(ISO_ROOT)"

verify: $(ISO)
	test -s "$(ISO)"
	file "$(ISO)"
	isoinfo -R -f -i "$(ISO)" | tee "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/BUILD-LABEL.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/XNU-UPSTREAM.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -q '/xnu-kernel/xnu-kernel-artifacts.txt' "$(BUILD_DIR)/iso-contents.txt"
	grep -Eq '/xnu-kernel/.*/kernel(\.release)?$$|/xnu-kernel/.*/mach(\.release)?$$' "$(BUILD_DIR)/iso-contents.txt"

clean:
	rm -rf build
