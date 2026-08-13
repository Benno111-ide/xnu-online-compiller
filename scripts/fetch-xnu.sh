#!/usr/bin/env sh
set -eu

dest="${1:-build/xnu-source}"

if [ ! -f xnu-upstream.env ]; then
    echo "xnu-upstream.env is missing" >&2
    exit 1
fi

. ./xnu-upstream.env

if [ -z "${XNU_REPO_URL:-}" ] || [ -z "${XNU_REF:-}" ] || [ -z "${XNU_COMMIT:-}" ]; then
    echo "xnu-upstream.env must define XNU_REPO_URL, XNU_REF, and XNU_COMMIT" >&2
    exit 1
fi

if [ -d "$dest/.git" ]; then
    current="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
    if [ "$current" = "$XNU_COMMIT" ]; then
        echo "XNU source already present at $XNU_COMMIT"
        exit 0
    fi
fi

rm -rf "$dest"
mkdir -p "$dest"

git init "$dest"
git -C "$dest" remote add origin "$XNU_REPO_URL"
git -C "$dest" fetch --depth 1 origin "$XNU_COMMIT"
git -C "$dest" checkout --detach FETCH_HEAD

actual="$(git -C "$dest" rev-parse HEAD)"
if [ "$actual" != "$XNU_COMMIT" ]; then
    echo "Expected XNU commit $XNU_COMMIT but fetched $actual" >&2
    exit 1
fi

echo "Fetched XNU $actual into $dest"
