#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <opencore-output-dir>" >&2
    exit 2
fi

dst=$1
case "$dst" in
    build/*|./build/*|*/build/*) ;;
    *)
        echo "refusing to replace non-build OpenCore directory: $dst" >&2
        exit 2
        ;;
esac

. ./xnu-upstream.env

normalize_opencore_config() {
    config=$1
    python3 - "$config" <<'PY'
from pathlib import Path
import plistlib
import sys

config = Path(sys.argv[1])
with config.open("rb") as f:
    plist = plistlib.load(f)

misc = plist.setdefault("Misc", {})
security = misc.setdefault("Security", {})
security["SecureBootModel"] = "Disabled"
security["Vault"] = "Optional"

uefi = plist.setdefault("UEFI", {})
uefi["Drivers"] = [
    {
        "Arguments": "",
        "Comment": "OpenCore runtime services",
        "Enabled": True,
        "LoadEarly": False,
        "Path": "OpenRuntime.efi",
    },
    {
        "Arguments": "",
        "Comment": "HFS+ filesystem support bundled with OpenCore",
        "Enabled": True,
        "LoadEarly": False,
        "Path": "OpenHfsPlus.efi",
    },
]

with config.open("wb") as f:
    plistlib.dump(plist, f, sort_keys=False)
PY
}

if [ -s "$dst/X64/EFI/BOOT/BOOTx64.efi" ] &&
   [ -s "$dst/X64/EFI/OC/OpenCore.efi" ] &&
   [ -s "$dst/X64/EFI/OC/config.plist" ]; then
    normalize_opencore_config "$dst/X64/EFI/OC/config.plist"
    exit 0
fi

tmp="${dst}.tmp"
archive="${tmp}/OpenCore.zip"

rm -rf "$tmp"
mkdir -p "$tmp"

curl -fsSL "$OPENCORE_BINARY_URL" -o "$archive"
printf '%s  %s\n' "$OPENCORE_BINARY_SHA256" "$archive" | shasum -a 256 -c -
python3 - "$archive" "$tmp" <<'PY'
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
target = Path(sys.argv[2])
with zipfile.ZipFile(archive) as zf:
    zf.extractall(target)
PY
rm -f "$archive"

test -s "$tmp/X64/EFI/BOOT/BOOTx64.efi"
test -s "$tmp/X64/EFI/OC/OpenCore.efi"
test -s "$tmp/X64/EFI/OC/Drivers/OpenRuntime.efi"
test -s "$tmp/X64/EFI/OC/Drivers/OpenHfsPlus.efi"

if [ ! -s "$tmp/X64/EFI/OC/config.plist" ]; then
    if [ -s "$tmp/Docs/Sample.plist" ]; then
        cp "$tmp/Docs/Sample.plist" "$tmp/X64/EFI/OC/config.plist"
    else
        echo "OpenCore release did not contain X64/EFI/OC/config.plist or Docs/Sample.plist" >&2
        exit 1
    fi
fi

normalize_opencore_config "$tmp/X64/EFI/OC/config.plist"

rm -rf "$dst"
mv "$tmp" "$dst"
