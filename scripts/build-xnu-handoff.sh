#!/usr/bin/env sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <amd64|arm64> <work-dir> <output-elf>" >&2
    exit 2
fi

arch=$1
work=$2
output=$3

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kernel_c="$script_dir/bootstub.c"
linker="$script_dir/bootstub.ld"
object="$work/bootstub.o"

llvm_prefix=$(brew --prefix llvm 2>/dev/null || true)
lld_prefix=$(brew --prefix lld 2>/dev/null || true)
clang="${CLANG:-${llvm_prefix:+$llvm_prefix/bin/clang}}"
ld_lld="${LD_LLD:-${lld_prefix:+$lld_prefix/bin/ld.lld}}"

if [ -n "${XNU_HANDOFF_JUMP+x}" ]; then
    handoff_jump=$XNU_HANDOFF_JUMP
elif [ "$arch" = "arm64" ]; then
    handoff_jump=1
else
    handoff_jump=0
fi
handoff_debug="${XNU_HANDOFF_DEBUG:-0}"

if [ -z "$clang" ] || [ ! -x "$clang" ]; then
    clang="${CLANG:-clang}"
fi
if [ -z "$ld_lld" ] || [ ! -x "$ld_lld" ]; then
    ld_lld="${LD_LLD:-ld.lld}"
fi

command -v "$clang" >/dev/null 2>&1
command -v "$ld_lld" >/dev/null 2>&1

if [ ! -f "$kernel_c" ]; then
    echo "missing C source: $kernel_c" >&2
    exit 1
fi
if [ ! -f "$linker" ]; then
    echo "missing linker script: $linker" >&2
    exit 1
fi

mkdir -p "$work" "$(dirname "$output")"

case "$arch" in
    amd64)
        target=x86_64-unknown-elf
        linker_machine=elf_x86_64
        cflags="-mno-red-zone -mcmodel=kernel -mno-sse -mno-sse2 -mno-mmx -msoft-float"
        ;;
    arm64)
        target=aarch64-unknown-elf
        linker_machine=aarch64elf
        cflags="-mcpu=generic -march=armv8-a+nofp+nosimd -mgeneral-regs-only"
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 2
        ;;
esac

"$clang" \
    -target "$target" \
    -ffreestanding \
    -fno-stack-protector \
    -fno-pic \
    -fno-pie \
    -fno-builtin \
    -O2 \
    "-DXNU_HANDOFF_JUMP=$handoff_jump" \
    "-DXNU_HANDOFF_DEBUG=$handoff_debug" \
    $cflags \
    -Wall \
    -Wextra \
    -c "$kernel_c" \
    -o "$object"

"$ld_lld" \
    -m "$linker_machine" \
    -no-pie \
    -z max-page-size=0x1000 \
    -T "$linker" \
    --build-id=none \
    "$object" \
    -o "$output"

file "$output"
