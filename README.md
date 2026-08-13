# xnu online compiller

This repository builds Apple XNU source ISOs for:

- `amd64`
- `arm64`

The build uses Apple's official XNU source from
<https://github.com/apple-oss-distributions/xnu>. The pinned upstream revision
is recorded in `xnu-upstream.env`; CI fetches that exact commit, verifies the
expected XNU source tree, packages that external tree into each ISO, verifies the
ISO contents, and uploads the ISO as a workflow artifact.

There is no local placeholder kernel source in this repository. Apple XNU's own
README documents that compiling the real kernel requires Apple SDK/KDK inputs,
so this Ubuntu CI produces reproducible source ISOs from the external XNU tree
rather than compiling a fake built-in kernel.

Run the same build on an Ubuntu machine with:

```sh
sudo apt-get install -y file genisoimage git make xorriso
make ARCH=amd64 all
make ARCH=arm64 all
```

The upstream XNU source is fetched into `build/xnu-source` by default. Update
`xnu-upstream.env` to point at a newer Apple commit when you want to refresh the
integrated source revision.
