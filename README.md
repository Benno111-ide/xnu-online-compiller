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

By default, the build creates a small bundled fallback EFI app. That app makes
the ISO UEFI-bootable and reports that `/boot/xnu-kernel.macho` is bundled, but
it does not perform Apple's proprietary `boot.efi`/iBoot platform handoff.

For `amd64`, `XNU_EFI_VENDOR=opencore` can be used to package OpenCore from
Acidanthera's OpenCorePkg release. OpenCore is XNU/macOS-oriented, but it is
designed to chain into Apple `boot.efi`/macOS boot volumes rather than directly
execute this ISO's raw `/boot/xnu-kernel.macho`, so it is opt-in.

Set
`XNU_EFI_LOADER=/path/to/BOOTX64.EFI` or
`XNU_EFI_LOADER=/path/to/BOOTAA64.EFI` to override the default EFI with a
specific loader.

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
