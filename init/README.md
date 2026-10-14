# xnu-init

`xnu-init` is a small C/POSIX PID 1 for an experimental Darwin userspace. It
starts jobs in configuration order, waits for each `once` job to succeed,
supervises foreground services, and reaps adopted children. It uses process
groups to stop services and their descendants. Failed services restart after
1, 2, 4, 8, 16, then 30 seconds; running for at least 30 seconds resets that
delay. A failed `once` job stops startup and shuts down started services.

Build the Darwin overlay with macOS/Xcode:

```sh
make ARCH=amd64 build-init
make ARCH=arm64 build-init
```

Outputs are `build/<arch>/xnu-init/rootfs/`, `xnu-init-rootfs.tar`, and
`xnu-init-manifest.txt`. The normal ISO build includes the tar and manifest
in `/userspace/` on the ISO and its FAT EFI image. `make verify` checks those
files and the overlay's required entries. `XNU_INCLUDE_INIT=0` skips building
and packaging init for kernel-only builds.

Install the overlay into a **dedicated experimental Darwin root volume**:

```sh
tar -C /path/to/darwin-root -xpf build/amd64/xnu-init/xnu-init-rootfs.tar
```

This replaces that volume's `/sbin/launchd` with a symlink to `xnu-init`. The
pinned XNU selects `/sbin/launchd` in
[`bsd/kern/kern_exec.c`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_exec.c).
No kernel patch or custom init boot argument is needed. XNU's `-s` argument
starts only a supervised single-user console, bypassing the configured jobs.

The root volume must already provide a compatible `/bin/sh`, `/usr/lib/dyld`,
libSystem and its dependencies, and `/dev/console`. The loader and kernel must
support reaching and mounting that root volume. This repository's kernel ISO
alone does not supply that userspace or prove a boot to PID 1. The binary is
dynamically linked against the macOS SDK's runtime; use a matching Darwin
userspace. This init does not implement launchd's Mach bootstrap services or
support running a normal macOS installation.

Edit `/etc/xnu-init/rc.boot` for synchronous machine setup, and
`/etc/xnu-init/services.conf` for services:

```text
# name | mode | shell command
bootstrap | once | /bin/sh /etc/xnu-init/rc.boot
worker | respawn | exec /usr/local/sbin/worker --foreground
console | console | exec /bin/sh -i
```

The first two `|` characters delimit fields. The remaining text is passed
to `/bin/sh -c`, so quoting, pipelines, and environment assignments use shell
syntax. Names must be unique and contain letters, digits, `_`, or `-`; at
most 64 services and 4094 characters per definition are supported. Blank
lines and lines starting with `#` are ignored. Configuration is trusted root
code; protect it like a startup script.

`once` jobs are startup barriers. `respawn` jobs start asynchronously and
must remain in the foreground. `console` behaves like `respawn` and also
opens `/dev/console` as a controlling terminal in a new session. Exit of a
service kills any remaining processes in its group before restart; processes
that deliberately create another session escape that group. The shipped
console is an unauthenticated root rescue shell for an isolated VM. Replace
it with a foreground getty/login service for authenticated access.

SIGTERM, SIGINT, and SIGHUP stop startup/restarts, send SIGTERM to service
groups in reverse configuration order, then send SIGKILL after five seconds.
SIGHUP stops the supervisor; it does not reload configuration. PID 1 syncs
filesystems and stays alive reaping children after shutdown or a startup
error. It does not unmount volumes, reboot, or power off the machine. A host
development supervisor exits with status 1 on startup failure and 0 on a
requested stop.

Validate configuration or run a development supervisor without taking over
PID 1:

```sh
cc -std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror -O2 init/xnu-init.c -o /tmp/xnu-init
/tmp/xnu-init --check --config init/services.conf
/tmp/xnu-init --user --config /path/to/development-services.conf
make test-init
```

Use your own configuration with `--user`: the bundled one refers to installed
paths and opens the system console. `--check` parses without running commands.
The test suite compiles the real supervisor with warnings treated as errors
and checks parsing, ordered startup, failure handling, restart backoff, and
termination of descendants ignoring SIGTERM. CI runs it on Linux and macOS,
and the ISO jobs build overlays for both target architectures. Host tests do
not exercise PID 1 adoption, the controlling console, or the Darwin boot path.
