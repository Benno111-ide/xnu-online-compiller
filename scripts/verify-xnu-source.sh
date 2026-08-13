#!/usr/bin/env sh
set -eu

src="${1:-build/xnu-source}"

if [ ! -f xnu-upstream.env ]; then
    echo "xnu-upstream.env is missing" >&2
    exit 1
fi

. ./xnu-upstream.env

if [ ! -d "$src/.git" ]; then
    echo "XNU source directory is missing: $src" >&2
    exit 1
fi

actual="$(git -C "$src" rev-parse HEAD)"
if [ "$actual" != "$XNU_COMMIT" ]; then
    echo "Expected XNU commit $XNU_COMMIT but found $actual" >&2
    exit 1
fi

for path in APPLE_LICENSE README.md Makefile bsd osfmk iokit libkern libsa pexpert config; do
    if [ ! -e "$src/$path" ]; then
        echo "Required XNU path is missing: $path" >&2
        exit 1
    fi
done

grep -q "XNU kernel is part of the Darwin operating system" "$src/README.md"
grep -q "Apple Public Source License" "$src/APPLE_LICENSE"

echo "Verified Apple XNU source at $actual"
