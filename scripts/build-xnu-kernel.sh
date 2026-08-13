#!/usr/bin/env sh
set -eu

arch="${1:?usage: build-xnu-kernel.sh <amd64|arm64> <xnu-source> <output-dir>}"
src="${2:?usage: build-xnu-kernel.sh <amd64|arm64> <xnu-source> <output-dir>}"
out="${3:?usage: build-xnu-kernel.sh <amd64|arm64> <xnu-source> <output-dir>}"

case "$arch" in
    amd64)
        xnu_arch="X86_64"
        ;;
    arm64)
        xnu_arch="ARM64"
        ;;
    *)
        echo "Unsupported architecture: $arch" >&2
        exit 1
        ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
    echo "A proper Apple XNU kernel build requires macOS/Xcode tools." >&2
    exit 1
fi

sh "$(dirname "$0")/verify-xnu-source.sh" "$src"

mkdir -p "$out"
out_abs="$(cd "$out" && pwd)"
objroot="$out_abs/obj"
dstroot="$out_abs/dst"
symroot="$out_abs/sym"
artifact_root="$out_abs/artifacts"
manifest="$out_abs/xnu-kernel-artifacts.txt"
build_log="$out_abs/xnu-build.log"

rm -rf "$objroot" "$dstroot" "$symroot" "$artifact_root" "$manifest" "$build_log"
mkdir -p "$objroot" "$dstroot" "$symroot" "$artifact_root"

if [ "$arch" = "arm64" ]; then
    arm64_macos_config="$src/config/MASTER.arm64.MacOSX"
    if [ -f "$arm64_macos_config" ] && ! grep -q "KERNEL_BASE =.*nos_arm_asm.*nos_arm_pmap" "$arm64_macos_config"; then
        perl -0pi -e 's/(KERNEL_BASE =\s*\[\s*arm64\b)(?![^\]]*nos_arm_asm)/$1 nos_arm_asm nos_arm_pmap/' "$arm64_macos_config"
    fi

    arm_pmap="$src/osfmk/arm/pmap/pmap.c"
    if [ -f "$arm_pmap" ] && ! grep -q "XNU_OPEN_SOURCE_ARM64_PMAP_COMPAT" "$arm_pmap"; then
        perl -0pi -e 's@(#ifdef CONFIG_XNUPOST\s*\n#include <tests/xnupost.h>\s*\n#endif\s*\n)@$1\n#ifndef XNU_OPEN_SOURCE_ARM64_PMAP_COMPAT\n#define XNU_OPEN_SOURCE_ARM64_PMAP_COMPAT\nstatic void pmap_ppl_lockdown_page(vm_address_t kva, uint64_t lockdown_flag, bool ppl_writable);\nstatic void pmap_ppl_unlockdown_page(vm_address_t kva, uint64_t lockdown_flag, bool ppl_writable);\nstatic void pmap_phys_write_disable(vm_address_t va);\n#ifndef ptep_get_iommu\n#define ptep_get_iommu(pte_p) ((void *)0)\n#endif\n#define pmap_ppl_lockdown_pages(kva, size, lockdown_flag, ppl_writable) do { \\\n    for (vm_address_t _xnu_kva = trunc_page(kva), _xnu_end = round_page((kva) + (size)); \\\n        _xnu_kva < _xnu_end; _xnu_kva += PAGE_SIZE) { \\\n        pmap_ppl_lockdown_page(_xnu_kva, lockdown_flag, ppl_writable); \\\n    } \\\n} while (0)\n#define pmap_ppl_unlockdown_pages(kva, size, lockdown_flag, ppl_writable) do { \\\n    for (vm_address_t _xnu_kva = trunc_page(kva), _xnu_end = round_page((kva) + (size)); \\\n        _xnu_kva < _xnu_end; _xnu_kva += PAGE_SIZE) { \\\n        pmap_ppl_unlockdown_page(_xnu_kva, lockdown_flag, ppl_writable); \\\n    } \\\n} while (0)\n#endif\n@' "$arm_pmap"
    fi

    rorgn_ppl="$src/osfmk/arm64/amcc_rorgn_ppl.c"
    if [ ! -f "$rorgn_ppl" ]; then
        cat > "$rorgn_ppl" <<'SOURCE'
#include <stdbool.h>
#include <mach/vm_types.h>

void
rorgn_stash_range(void)
{
}

void
rorgn_lockdown(void)
{
}

bool
rorgn_contains(vm_offset_t addr, vm_size_t size, bool defval)
{
	(void)addr;
	(void)size;
	return defval;
}

void
rorgn_validate_core(void)
{
}
SOURCE
    fi

    for rorgn_missing in \
        "$src/osfmk/arm64/amcc_rorgn_ppl_amcc.c" \
        "$src/osfmk/arm64/amcc_rorgn_common.c" \
        "$src/osfmk/arm64/amcc_rorgn_pv_ctrr.c"
    do
        if [ ! -f "$rorgn_missing" ]; then
            printf '/* Public XNU standalone ARM64 RORGN placeholder. */\n' > "$rorgn_missing"
        fi
    done

    arm64_tunables="$src/osfmk/arm64/tunables/tunables.s"
    if [ ! -f "$arm64_tunables" ]; then
        mkdir -p "$(dirname "$arm64_tunables")"
        cat > "$arm64_tunables" <<'SOURCE'
.macro APPLY_TUNABLES tmp0, tmp1, tmp2
.endmacro
SOURCE
    fi

    vmapple_config="$src/pexpert/pexpert/arm64/VMAPPLE.h"
    if [ -f "$vmapple_config" ] && ! grep -q "NO_CPU_OVRD" "$vmapple_config"; then
        perl -0pi -e 's@(#define HAS_PARAVIRTUALIZED_CTRR\s+1\s*\n)@$1#define NO_CPU_OVRD                1\n@' "$vmapple_config"
    fi
fi

: "${RC_DARWIN_KERNEL_VERSION:=9999.0.0}"

echo "Building Apple XNU $xnu_arch RELEASE kernel"
echo "SRCROOT=$src"
echo "OBJROOT=$objroot"
echo "DSTROOT=$dstroot"
echo "SYMROOT=$symroot"
echo "LOG=$build_log"

set +e
make -C "$src" \
    SDKROOT=macosx \
    HOST_SDKROOT=macosx \
    ARCH_CONFIGS="$xnu_arch" \
    KERNEL_CONFIGS=RELEASE \
    RC_DARWIN_KERNEL_VERSION="$RC_DARWIN_KERNEL_VERSION" \
    VERBOSE=YES \
    MAKEJOBS=--jobs=1 \
    BUILD_WERROR=0 \
    BUILD_LTO=0 \
    BUILD_DSYM=0 \
    CFLAGS_EXTRA="-Wno-pointer-to-int-cast -Wno-error=pointer-to-int-cast" \
    OBJROOT="$objroot" \
    DSTROOT="$dstroot" \
    SYMROOT="$symroot" \
    install_kernels > "$build_log" 2>&1
make_status=$?
set -e

if [ "$make_status" -ne 0 ]; then
    echo "XNU build failed with exit code $make_status. Last 200 log lines:" >&2
    tail -n 200 "$build_log" >&2 || true
    exit "$make_status"
fi

find "$objroot" "$dstroot" "$symroot" -type f \
    \( -name 'kernel*' -o -name 'mach*' -o -name 'libkernel*.a' -o -name 'compile_commands.json' \) \
    | sort > "$manifest"

if [ ! -s "$manifest" ]; then
    echo "XNU build completed without discoverable kernel artifacts." >&2
    exit 1
fi

while IFS= read -r file; do
    rel="${file#$out_abs/}"
    mkdir -p "$artifact_root/$(dirname "$rel")"
    cp "$file" "$artifact_root/$rel"
done < "$manifest"

cp "$manifest" "$artifact_root/xnu-kernel-artifacts.txt"

echo "Collected XNU kernel artifacts:"
cat "$manifest"
