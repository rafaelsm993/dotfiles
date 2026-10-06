#!/bin/sh
# Minimal POSIX shim: a fresh Arch install has no fish yet.
# Installs the bare minimum, then hands off to bootstrap.fish.
#
#   ./bootstrap.sh [--dry-run] [--force] [--only PHASE] [--skip PHASE]
#
# All arguments are passed straight through to bootstrap.fish.
set -eu

if [ ! -f /etc/arch-release ]; then
    echo "This script targets Arch Linux." >&2
    exit 1
fi

if [ "$(id -u)" = 0 ]; then
    echo "Do not run as root; run as your normal user." >&2
    exit 1
fi

# Only shell out to sudo/pacman when something is actually missing, so
# re-running (and --dry-run) stays cheap and needs no password.
missing=""
for pkg in fish git stow; do
    if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
    fi
done

if [ -n "$missing" ]; then
    echo "==> Installing bootstrap prerequisites:$missing"
    # shellcheck disable=SC2086
    sudo pacman -Syu --needed --noconfirm $missing
else
    echo "==> Bootstrap prerequisites already present (fish, git, stow)"
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Handing off to bootstrap.fish"
exec fish "$DIR/bootstrap.fish" "$@"
