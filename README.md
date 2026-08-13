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

There is no local placeholder kernel source in this repository. The build fails
unless Apple XNU's external source tree produces real kernel artifacts.

Run the same build on an Ubuntu machine with:

```sh
brew install xorriso
make ARCH=amd64 all
make ARCH=arm64 all
```

The upstream XNU source is fetched into `build/xnu-source` by default. Update
`xnu-upstream.env` to point at a newer Apple commit when you want to refresh the
integrated source revision.
