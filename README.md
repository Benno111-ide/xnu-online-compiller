# xnu online compiller

This repository builds Apple XNU kernel ISOs for:

- `amd64`
- `arm64`

The build uses Apple's official XNU source from
<https://github.com/apple-oss-distributions/xnu>. The pinned upstream revision
is recorded in `xnu-upstream.env`; CI fetches that exact commit, verifies the
expected XNU source tree, invokes Apple XNU's own Makefile on macOS/Xcode,
packages the produced kernel artifacts into each ISO, verifies the ISO contents,
and uploads the ISO as a workflow artifact.

Each ISO includes a Limine EFI El Torito boot image with the standard fallback
loader path for the target architecture:

- `EFI/BOOT/BOOTX64.EFI` for `amd64`
- `EFI/BOOT/BOOTAA64.EFI` for `arm64`

Limine is fetched from the pinned official binary release recorded in
`xnu-upstream.env`. CI verifies the Limine checksum, the ISO fallback EFI path,
the embedded EFI boot image, `limine.conf`, the XNU kernel artifacts, and a
QEMU/UEFI smoke boot that checks the Limine menu renders and then successfully
loads the `bootloader.sys` ELF handoff stub.

There is no local placeholder kernel source in this repository. By default, the
build fails unless Apple XNU's external source tree produces real kernel
artifacts. The boot entry itself is a small Limine-compatible ELF stub because
Limine's native protocol loader does not load Apple's raw Mach-O kernel artifact
directly. When booted, that stub loads the XNU Mach-O module, stages its
segments, builds XNU-style boot arguments, builds a minimal Apple device tree,
displays a diagnostic handoff screen, and jumps into XNU. On `arm64`, the
jump includes a physical boot-args handoff and a low `TTBR0_EL1` identity map.

Run the same build on an Ubuntu machine with:

```sh
brew install xorriso
brew install mtools
make ARCH=amd64 all
make ARCH=arm64 all
```

If you already have a built XNU Mach-O from a macOS/Xcode machine, package and
capture an arm64 handoff attempt from this workspace with:

```sh
make ARCH=arm64 XNU_KERNEL_ARTIFACT=/path/to/kernel.development handoff-boot
```

That target rebuilds the arm64 stub, packages the external kernel as
`/boot/xnu-kernel.macho`, boots QEMU, and writes the capture report under
`build/arm64/limine-smoke/`.

Before packaging, `scripts/validate-xnu-macho.py` checks that the selected
kernel artifact is a Mach-O/FAT Mach-O with the requested architecture slice,
valid segment ranges, and a usable entry point. The validation summary is
stored in `/xnu-kernel/xnu-kernel-validation.txt` inside the ISO tree.
`handoff-boot` also captures a short boot timeline: `limine-smoke.ppm`,
intermediate `limine-booted-*.ppm` frames, the final `limine-booted.ppm`,
`serial.log`, and `limine-smoke.txt`.

The upstream XNU source is fetched into `build/xnu-source` by default. Update
`xnu-upstream.env` to point at a newer Apple commit when you want to refresh the
integrated source revision.
