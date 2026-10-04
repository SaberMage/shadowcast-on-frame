#!/bin/bash
# Run at boot by shadowcast-on-frame.service (as root). Loads the UVC driver
# modules for the running kernel, building them first if this kernel doesn't
# have any yet (i.e. right after a SteamOS update).
set -u
ROOT="${SHADOWCAST_ROOT:-/srv/shadowcast-on-frame}"  # override only for testing
KVER="$(uname -r)"
DIR="$ROOT/$KVER"

if [ ! -f "$DIR/load-order" ]; then
    echo "No UVC modules for kernel $KVER yet (SteamOS updated?); building them."
    # The build downloads Valve's headers and the upstream driver source.
    for i in $(seq 60); do
        curl -fsS --connect-timeout 5 -o /dev/null https://api.github.com && break
        [ "$i" = 1 ] && echo "Waiting for the network..."
        sleep 5
    done
    TMP="$(mktemp -d "$ROOT/.build-$KVER.XXXXXX")"
    if TMPDIR=/var/tmp "$ROOT/build.sh" "$TMP"; then
        rm -rf "$DIR" && mv "$TMP" "$DIR" && chmod 755 "$DIR"
        # Keep only this kernel's build.
        for old in "$ROOT"/*/; do
            [ "${old%/}" = "$DIR" ] || rm -rf "$old"
        done
    else
        rm -rf "$TMP"
        echo "Build failed; run install.sh from the shadowcast-on-frame repo to retry."
        exit 1
    fi
fi

rc=0
while read -r m; do
    [ -n "$m" ] || continue
    if grep -q "^${m//-/_} " /proc/modules; then
        echo "$m already loaded"
    elif insmod "$DIR/$m.ko"; then
        echo "loaded $m"
    else
        echo "failed to load $m"
        rc=1
    fi
done < "$DIR/load-order"
exit $rc
