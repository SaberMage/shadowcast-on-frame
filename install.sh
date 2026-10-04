#!/bin/bash
# shadowcast-on-frame: add USB Video Class (UVC) support to Steam Frame, so the
# Genki ShadowCast (and other USB capture cards and webcams) show up as cameras.
#
# Builds the uvcvideo driver (plus whichever of its helpers the kernel lacks)
# from the upstream Linux sources that match your kernel, against Valve's
# matching kernel headers, then installs them with a boot service.
#
#   ./install.sh      build, install and load (asks for your sudo password once)
#
# After a SteamOS update that changes the kernel, the boot service rebuilds the
# driver by itself (it needs a network connection at boot).
set -euo pipefail

INSTALL_DIR=/srv/shadowcast-on-frame   # on the persistent home partition
SERVICE=shadowcast-on-frame.service
REPO="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight -----------------------------------------------------------------
[ "$(uname -m)" = aarch64 ] || die "this is for Steam Frame (aarch64)"
grep -q '^ID=steamos' /etc/os-release || die "this is for SteamOS"
[ "$EUID" -ne 0 ] || die "run as your normal user (it asks for sudo when needed)"
for tool in pacman curl bsdtar make gcc python3 modinfo sudo; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

KVER="$(uname -r)"
# Only a driver shipped with the kernel counts (a hand-loaded one doesn't).
if modinfo -k "$KVER" uvcvideo >/dev/null 2>&1; then
    say "This kernel already ships UVC support; nothing to do."
    exit 0
fi

WORK="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/shadowcast-on-frame.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TMPDIR="$WORK" "$REPO/src/build.sh" "$WORK/out" | sed 's/^==> /\x1b[1m==> /; s/$/\x1b[0m/' ||
    die "build failed"
mapfile -t MODULES < "$WORK/out/load-order"

# --- install (root) ----------------------------------------------------------------
say "Installing (sudo)"
sudo install -d -m 755 "$INSTALL_DIR/$KVER"
for m in "${MODULES[@]}"; do
    sudo install -m 644 "$WORK/out/$m.ko" "$INSTALL_DIR/$KVER/$m.ko"
done
sudo install -m 644 "$WORK/out/load-order" "$INSTALL_DIR/$KVER/load-order"
sudo install -m 755 "$REPO/src/build.sh" "$INSTALL_DIR/build.sh"
sudo install -m 755 "$REPO/src/load.sh" "$INSTALL_DIR/load.sh"
sudo install -m 644 "$REPO/src/$SERVICE" "/etc/systemd/system/$SERVICE"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE" >/dev/null 2>&1
sudo systemctl restart "$SERVICE"

# --- report ------------------------------------------------------------------------
sleep 1
say "Done. UVC driver loaded, set to load at every boot, and rebuilt automatically after kernel updates."
found=0
for d in /sys/class/video4linux/video*; do
    [ -e "$d/device/driver" ] || continue
    [ "$(basename "$(readlink "$d/device/driver")")" = uvcvideo ] || continue
    echo "    /dev/${d##*/}: $(cat "$d/name")"
    found=1
done
[ "$found" = 1 ] || echo "    No UVC device attached right now. Plug your capture card or webcam in."
echo "    Reload the page or restart the browser/app that should see it."
