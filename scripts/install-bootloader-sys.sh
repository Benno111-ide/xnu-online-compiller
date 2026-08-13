#!/usr/bin/env sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <xnu-artifacts-dir> <bootloader-output>" >&2
    exit 2
fi

artifacts=$1
output=$2

manifest="$artifacts/xnu-kernel-artifacts.txt"
if [ ! -s "$manifest" ]; then
    echo "missing XNU artifact manifest: $manifest" >&2
    exit 1
fi

kernel=$(
    find "$artifacts" -type f \
        \( -name 'kernel' -o -name 'kernel.release' -o -name 'mach' -o -name 'mach.release' \) \
        | sort \
        | head -n 1
)

if [ -z "$kernel" ]; then
    echo "no kernel or mach artifact found under $artifacts" >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"
cp "$kernel" "$output"
echo "Installed $kernel as $output"
