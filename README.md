# xnu online compiller

This repository builds tiny XNU-branded freestanding kernel artifacts for:

- `amd64`
- `arm64`

GitHub Actions compiles both targets, packages each kernel into an ISO, verifies
the ISO contents, and uploads the kernel plus ISO as workflow artifacts.

Run the same build on an Ubuntu machine with:

```sh
sudo apt-get install -y clang file genisoimage grub-pc-bin lld make mtools xorriso
make ARCH=amd64 all
make ARCH=arm64 all
```
