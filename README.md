# xnu online compiller

This repository builds Apple XNU kernel ISOs for:

- `amd64`
- `arm64`

The build uses Apple's official XNU source from
<https://github.com/apple-oss-distributions/xnu>. The pinned upstream revision
is recorded in `xnu-upstream.env`; CI fetches that exact commit, verifies the
expected XNU source tree, invokes Apple XNU's own Makefile on macOS/Xcode,
packages the produced kernel artifacts into a bootable UEFI ISO, verifies the
ISO contents, and uploads the ISO as a workflow artifact.

Each ISO includes an EFI application at the standard fallback path for the
target architecture:

- `EFI/BOOT/BOOTX64.EFI` for `amd64`
- `EFI/BOOT/BOOTAA64.EFI` for `arm64`

For `amd64`, the default EFI is OpenCore from Acidanthera's OpenCorePkg release.
OpenCore is an XNU/macOS-oriented UEFI bootloader with Apple-specific UEFI
support and an XNU patch/injection engine. The ISO bundles both
`EFI/BOOT/BOOTX64.EFI` and `EFI/OC`.

For `arm64`, the build still creates a small bundled fallback EFI app because
OpenCore's release payload is X64 and Apple's arm64 `boot.efi`/iBoot path is
not available from the open XNU source tree. Set
`XNU_EFI_LOADER=/path/to/BOOTX64.EFI` or
`XNU_EFI_LOADER=/path/to/BOOTAA64.EFI` to override the default EFI with a
specific loader.

The default kernel flags are:

```sh
XNU_BOOT_ARGS="-v keepsyms=1 debug=0x144 serial=3"
```

For OpenCore builds, these are written to
`NVRAM/Add/7C436110-AB2A-4BBB-A880-FE41995C9F82/boot-args` in
`EFI/OC/config.plist`. The ISO also includes `BOOT-ARGS.txt` with the same
value.

There is no local placeholder kernel source in this repository. By default, the
build fails unless Apple XNU's external source tree produces real kernel
artifacts. The ISO no longer builds or packages the old Limine
`bootloader.sys` handoff stub.

Run the same build on an Ubuntu machine with:

```sh
brew install xorriso
brew install mtools
make ARCH=amd64 all
make ARCH=arm64 all
```

If you already have a built XNU Mach-O from a macOS/Xcode machine, package it
with the default EFI from this workspace with:

```sh
make ARCH=arm64 XNU_KERNEL_ARTIFACT=/path/to/kernel.development iso verify smoke-boot
```

To use a real XNU/Darwin EFI handoff loader instead:

```sh
make ARCH=arm64 \
  XNU_KERNEL_ARTIFACT=/path/to/kernel.development \
  XNU_EFI_LOADER=/path/to/BOOTAA64.EFI \
  iso verify smoke-boot
```

That target packages the external kernel as `/boot/xnu-kernel.macho`, embeds
the EFI loader in `EFI/BOOT/`, boots QEMU, and writes the capture report under
`build/arm64/efi-smoke/`.

Before packaging, `scripts/validate-xnu-macho.py` checks that the selected
kernel artifact is a Mach-O/FAT Mach-O with the requested architecture slice,
valid segment ranges, and a usable entry point. The validation summary is
stored in `/xnu-kernel/xnu-kernel-validation.txt` inside the ISO tree.
`smoke-boot` also captures a short boot timeline and serial log under
`build/<arch>/efi-smoke/`.

The upstream XNU source is fetched into `build/xnu-source` by default. Update
`xnu-upstream.env` to point at a newer Apple commit when you want to refresh the
integrated source revision.
