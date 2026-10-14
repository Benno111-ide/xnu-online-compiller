#!/usr/bin/env sh
set -eu
arch="${1:?usage: build-xnu-init.sh <amd64|arm64> <output-dir>}"
out="${2:?usage: build-xnu-init.sh <amd64|arm64> <output-dir>}"
case "$arch" in
    amd64) target=x86_64 ;;
    arm64) target=arm64 ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 2 ;;
esac
if [ "$(uname -s)" != Darwin ]; then
    echo 'Darwin init artifacts require macOS/Xcode. Use make test-init for host tests.' >&2
    exit 1
fi
repo="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
mkdir -p "$out/rootfs/sbin" "$out/rootfs/etc/xnu-init"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang -arch "$target" -isysroot "$sdk" \
    -std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror -O2 \
    "$repo/init/xnu-init.c" -o "$out/rootfs/sbin/xnu-init"
chmod 755 "$out/rootfs/sbin/xnu-init"
# The pinned XNU starts /sbin/launchd, including on RELEASE kernels.
ln -sf xnu-init "$out/rootfs/sbin/launchd"
cp "$repo/init/services.conf" "$out/rootfs/etc/xnu-init/services.conf"
cp "$repo/init/rc.boot" "$out/rootfs/etc/xnu-init/rc.boot"
chmod 644 "$out/rootfs/etc/xnu-init/services.conf"
chmod 755 "$out/rootfs/etc/xnu-init/rc.boot"
printf 'arch=%s\ninit=/sbin/xnu-init\nkernel_init=/sbin/launchd\nconfig=/etc/xnu-init/services.conf\n' "$arch" > "$out/xnu-init-manifest.txt"
file "$out/rootfs/sbin/xnu-init"
tar -C "$out/rootfs" -cf "$out/xnu-init-rootfs.tar" sbin etc
echo "Darwin init overlay: $out/xnu-init-rootfs.tar"
