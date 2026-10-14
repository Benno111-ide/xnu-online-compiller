#!/bin/sh
set -eu
echo 'xnu-init: starting Darwin userspace'
# Add root filesystem specific setup here. The kernel must already have
# mounted a usable root with /dev/console, /bin/sh, dyld, and libSystem.
# Keep setup synchronous; long-lived services belong in services.conf.
