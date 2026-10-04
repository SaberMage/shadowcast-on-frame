#!/bin/bash
# Builds the UVC driver modules for the running kernel into <outdir>:
# the .ko files plus a load-order list. Used by install.sh (as your user) and
# by the boot service (as root) after a SteamOS update changes the kernel.
#
#   build.sh <outdir>
set -euo pipefail

OUT="${1:?usage: build.sh <outdir>}"
log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

for tool in pacman curl bsdtar make gcc python3 modinfo; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

KVER="$(uname -r)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/shadowcast-on-frame.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fetch() { curl --http1.1 -fsSL --retry 3 --connect-timeout 20 "$1" -o "$2"; }

# --- matching kernel headers -------------------------------------------------------
KPKG="$(cat "/usr/lib/modules/$KVER/pkgbase" 2>/dev/null)" ||
    die "can't tell which package provides kernel $KVER"
KPKGVER="$(pacman -Q "$KPKG" | awk '{print $2}')"
HPKG="$KPKG-headers"
log "Kernel $KVER ($KPKG $KPKGVER)"

HVER="$(pacman -Si "$HPKG" 2>/dev/null | awk -F': *' '/^Version/{print $2; exit}')" ||
    die "headers package $HPKG not found in your SteamOS repositories"
[ "$HVER" = "$KPKGVER" ] ||
    die "$HPKG in the repositories is $HVER, but your kernel is $KPKGVER (install the pending SteamOS update and reboot, then retry)"
log "Downloading $HPKG $HVER"
fetch "$(pacman -Sp "$HPKG" | tail -1)" "$WORK/headers.pkg.tar.zst"
mkdir -p "$WORK/headers"
bsdtar -xf "$WORK/headers.pkg.tar.zst" -C "$WORK/headers"
BUILD="$WORK/headers/usr/lib/modules/$KVER/build"
[ -f "$BUILD/Module.symvers" ] || die "unexpected headers package layout"

# --- upstream driver sources -------------------------------------------------------
# 6.18.0-gfbdbca41fd45 -> v6.18 ; 6.18.3-... -> v6.18.3
BASE="${KVER%%-*}"
TAG="v${BASE%.0}"
RAW="https://raw.githubusercontent.com/torvalds/linux/$TAG"
SRC="$WORK/src"
mkdir -p "$SRC"
log "Downloading the uvcvideo driver from Linux $TAG"
fetch "https://api.github.com/repos/torvalds/linux/contents/drivers/media/usb/uvc?ref=$TAG" "$WORK/uvc.json"
python3 - "$WORK/uvc.json" > "$WORK/uvc.files" <<'PY'
import json, sys
for f in json.load(open(sys.argv[1])):
    if f["name"].endswith((".c", ".h")):
        print(f["name"])
PY
while read -r f; do fetch "$RAW/drivers/media/usb/uvc/$f" "$SRC/$f"; done < "$WORK/uvc.files"

# uvcvideo's helpers: build only the ones this kernel doesn't already provide.
exported() { grep -qE "^0x[0-9a-f]+\s+$1\s" "$BUILD/Module.symvers"; }
MODULES=()
UVC_OBJS=$(cd "$SRC" && ls uvc_*.c | sed 's/\.c$/.o/' | tr '\n' ' ')
if ! exported uvc_format_by_guid; then
    fetch "$RAW/drivers/media/common/uvc.c" "$SRC/uvc.c"
    MODULES+=(uvc)
fi
if ! exported vb2_vmalloc_memops; then
    fetch "$RAW/drivers/media/common/videobuf2/videobuf2-vmalloc.c" "$SRC/videobuf2-vmalloc.c"
    MODULES+=(videobuf2-vmalloc)
fi
MODULES+=(uvcvideo)
{
    echo "obj-m += $(printf '%s.o ' "${MODULES[@]}")"
    echo "uvcvideo-objs := $UVC_OBJS"
} > "$SRC/Kbuild"

# --- build -------------------------------------------------------------------------
log "Building ${MODULES[*]}"
# CONFIG_DEBUG_INFO_BTF_MODULES= : skip BTF generation (needs pahole; not required to load).
make -C "$BUILD" M="$SRC" -j"$(nproc)" CONFIG_DEBUG_INFO_BTF_MODULES= modules \
    > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; die "build failed"; }
mkdir -p "$OUT"
for m in "${MODULES[@]}"; do
    vm="$(modinfo -F vermagic "$SRC/$m.ko")"
    [ "${vm%% *}" = "$KVER" ] || die "$m.ko was built for ${vm%% *}, not $KVER"
    cp "$SRC/$m.ko" "$OUT/"
done
printf '%s\n' "${MODULES[@]}" > "$OUT/load-order"
log "Built modules for $KVER"
