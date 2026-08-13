#!/usr/bin/env sh
set -eu

dst="${1:?usage: install-xnu-build-deps.sh <deps-dir>}"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Apple XNU build dependencies are only installed on macOS runners." >&2
    exit 1
fi

. ./xnu-upstream.env

sdkroot="$(xcrun -sdk macosx --show-sdk-path)"
availability_tool="$sdkroot/usr/local/libexec/availability.pl"

if [ -x "$availability_tool" ]; then
    echo "Found availability.pl in SDK: $availability_tool"
    exit 0
fi

src="$dst/AvailabilityVersions"
obj="$dst/AvailabilityVersions-obj"
sym="$dst/AvailabilityVersions-sym"
install_root="$dst/AvailabilityVersions-dst"

rm -rf "$src" "$obj" "$sym" "$install_root"
mkdir -p "$dst"

git init "$src"
git -C "$src" remote add origin "$AVAILABILITY_VERSIONS_REPO_URL"
git -C "$src" fetch --depth 1 origin "$AVAILABILITY_VERSIONS_COMMIT"
git -C "$src" checkout --detach FETCH_HEAD

actual_commit="$(git -C "$src" rev-parse HEAD)"
if [ "$actual_commit" != "$AVAILABILITY_VERSIONS_COMMIT" ]; then
    echo "Expected AvailabilityVersions $AVAILABILITY_VERSIONS_COMMIT, got $actual_commit" >&2
    exit 1
fi

cmake_bin="$(command -v cmake)"
ninja_bin="$(command -v ninja)"

make -C "$src" \
    CMAKE="$cmake_bin" \
    NINJA="$ninja_bin" \
    SRCROOT="$(pwd)/$src" \
    OBJROOT="$(pwd)/$obj" \
    SYMROOT="$(pwd)/$sym" \
    DSTROOT="$(pwd)/$install_root" \
    install

if [ ! -x "$install_root/usr/local/libexec/availability.pl" ]; then
    echo "AvailabilityVersions did not produce usr/local/libexec/availability.pl" >&2
    exit 1
fi

sudo mkdir -p "$sdkroot/usr/local"
sudo rsync -a "$install_root/usr/local/" "$sdkroot/usr/local/"

if [ ! -x "$availability_tool" ]; then
    echo "Failed to install availability.pl into $availability_tool" >&2
    exit 1
fi

kernel_private_headers="$sdkroot/System/Library/Frameworks/Kernel.framework/Versions/A/PrivateHeaders"
sudo mkdir -p \
    "$sdkroot/usr/local/include/kernel" \
    "$kernel_private_headers/AppleFeatures" \
    "$kernel_private_headers/platform"

if [ ! -f "$kernel_private_headers/AppleFeatures/AppleFeatures.h" ]; then
    cat > "$dst/AppleFeatures.h" <<'HEADER'
#ifndef APPLEFEATURES_H
#define APPLEFEATURES_H
#endif
HEADER
    sudo cp "$dst/AppleFeatures.h" "$kernel_private_headers/AppleFeatures/AppleFeatures.h"
fi

echo "Installed AvailabilityVersions $actual_commit into $sdkroot"
