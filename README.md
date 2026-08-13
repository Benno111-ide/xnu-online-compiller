# xnu online compiller

This repository builds tiny XNU-branded freestanding kernel artifacts for:

- `amd64`
- `arm64`

The build integrates Apple's official XNU source from
<https://github.com/apple-oss-distributions/xnu>. The pinned upstream revision
is recorded in `xnu-upstream.env`; CI fetches that exact commit, verifies the
expected XNU source tree, packages the upstream revision and Apple license into
each ISO, verifies the ISO contents, and uploads the kernel plus ISO as workflow
artifacts.

Run the same build on an Ubuntu machine with:

```sh
sudo apt-get install -y clang file genisoimage git grub-pc-bin lld make mtools xorriso
make ARCH=amd64 all
make ARCH=arm64 all
```

The upstream XNU source is fetched into `build/xnu-source` by default. Update
`xnu-upstream.env` to point at a newer Apple commit when you want to refresh the
integrated source revision.
