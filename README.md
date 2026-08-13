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
QEMU/UEFI smoke boot that checks the Limine menu actually renders.

There is no local placeholder kernel source in this repository. The build fails
unless Apple XNU's external source tree produces real kernel artifacts.

Run the same build on an Ubuntu machine with:

```sh
brew install xorriso
brew install mtools
make ARCH=amd64 all
make ARCH=arm64 all
```

The upstream XNU source is fetched into `build/xnu-source` by default. Update
`xnu-upstream.env` to point at a newer Apple commit when you want to refresh the
integrated source revision.
