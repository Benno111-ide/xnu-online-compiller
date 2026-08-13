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

rm -rf "$objroot" "$dstroot" "$symroot" "$artifact_root" "$manifest"
mkdir -p "$objroot" "$dstroot" "$symroot" "$artifact_root"

: "${RC_DARWIN_KERNEL_VERSION:=9999.0.0}"

echo "Building Apple XNU $xnu_arch RELEASE kernel"
echo "SRCROOT=$src"
echo "OBJROOT=$objroot"
echo "DSTROOT=$dstroot"
echo "SYMROOT=$symroot"

make -C "$src" \
    SDKROOT=macosx \
    HOST_SDKROOT=macosx \
    ARCH_CONFIGS="$xnu_arch" \
    KERNEL_CONFIGS=RELEASE \
    RC_DARWIN_KERNEL_VERSION="$RC_DARWIN_KERNEL_VERSION" \
    BUILD_WERROR=0 \
    BUILD_LTO=0 \
    BUILD_DSYM=0 \
    OBJROOT="$objroot" \
    DSTROOT="$dstroot" \
    SYMROOT="$symroot" \
    install_kernels

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
