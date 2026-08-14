#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <limine-output-dir>" >&2
    exit 2
fi

dst=$1
case "$dst" in
    build/*|./build/*|*/build/*) ;;
    *)
        echo "refusing to replace non-build Limine directory: $dst" >&2
        exit 2
        ;;
esac

. ./xnu-upstream.env

if [ -s "$dst/BOOTX64.EFI" ] && [ -s "$dst/BOOTAA64.EFI" ] && [ -s "$dst/LICENSE" ]; then
    exit 0
fi

tmp="${dst}.tmp"
archive="${tmp}/limine-binary.tar.xz"

rm -rf "$tmp"
mkdir -p "$tmp"

curl -fsSL "$LIMINE_BINARY_URL" -o "$archive"
printf '%s  %s\n' "$LIMINE_BINARY_SHA256" "$archive" | shasum -a 256 -c -
tar -C "$tmp" --strip-components=1 -xf "$archive"
rm -f "$archive"

test -s "$tmp/BOOTX64.EFI"
test -s "$tmp/BOOTAA64.EFI"
test -s "$tmp/LICENSE"

rm -rf "$dst"
mv "$tmp" "$dst"
