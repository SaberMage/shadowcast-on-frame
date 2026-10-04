#!/bin/bash
# Opens https://arcade.genkithings.com/ in Chromium's app mode, as its own
# window on Steam Frame's VR desktop. Run by the "Genki Arcade" launcher that
# genki-arcade-launcher.sh installs; logs to ~/.cache/genki-arcade.log.
URL="https://arcade.genkithings.com/"
CHROMIUM=org.chromium.Chromium
# Its own Chromium profile: otherwise a Chromium that's already running (for
# example one in the desktop session) takes over the launch and opens the
# window in its own session, which may not be on screen. It lives in the
# Flatpak's data folder, which its sandbox can always reach.
PROFILE="$HOME/.var/app/$CHROMIUM/genki-arcade"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/genki-arcade.log"
mkdir -p "$(dirname "$LOG")"
exec >"$LOG" 2>&1
echo "$(date '+%F %T') launching; DISPLAY=${DISPLAY:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DBUS=${DBUS_SESSION_BUS_ADDRESS:-}"

# Launches from the dashboard may come without a session bus address, which
# Flatpak needs; use the standard per-user bus socket.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
fi
# Draw on the VR desktop's X display. Chromium's Wayland backend doesn't end up
# there when launched from the dashboard.
unset WAYLAND_DISPLAY
export DISPLAY="${DISPLAY:-:0}"

exec /usr/bin/flatpak run "$CHROMIUM" --user-data-dir="$PROFILE" --ozone-platform=x11 --app="$URL"
