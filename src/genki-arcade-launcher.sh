#!/bin/bash
# Adds (or removes) a "Genki Arcade" launcher that opens
# https://arcade.genkithings.com/ in Chromium's app mode (its own window, no
# browser UI). Steam Frame's dashboard lists it under "+ > Launch Program",
# and desktop mode's app menu shows it too. Runs as your user; no sudo.
#
#   genki-arcade-launcher.sh install
#   genki-arcade-launcher.sh remove
set -euo pipefail

URL="https://arcade.genkithings.com/"
ICON_URL="https://arcade.genkithings.com/icons/arcade-256.png"
CHROMIUM=org.chromium.Chromium
PROFILE="$HOME/.var/app/$CHROMIUM/genki-arcade"   # see genki-arcade.sh
SCRIPT_DIR="$HOME/.local/share/genki-arcade"
DESKTOP="$HOME/.local/share/applications/genki-arcade.desktop"
ICON="$HOME/.local/share/icons/hicolor/256x256/apps/genki-arcade.png"

case "${1:-}" in
install)
    if ! flatpak info "$CHROMIUM" >/dev/null 2>&1; then
        echo "    Chromium (Flatpak) isn't installed, so no Genki Arcade launcher was added."
        echo "    Install Chromium from Discover, then re-run this to add one."
        exit 0
    fi
    mkdir -p "$(dirname "$DESKTOP")" "$(dirname "$ICON")" "$SCRIPT_DIR"
    install -m 755 "$(dirname "$(readlink -f "$0")")/genki-arcade.sh" "$SCRIPT_DIR/genki-arcade.sh"
    # The site's own app icon, fetched at install time; falls back to Chromium's.
    # Steam's app scanner only shows PNG icons that have an alpha channel, and
    # this one is plain RGB, so convert it to RGBA (ffmpeg is in the base image).
    icon_line="Icon=$CHROMIUM"
    if curl -fsSL --retry 2 "$ICON_URL" -o "$ICON.dl.png" &&
       ffmpeg -hide_banner -loglevel error -y -i "$ICON.dl.png" -pix_fmt rgba "$ICON.tmp.png" &&
       mv -f "$ICON.tmp.png" "$ICON"; then
        icon_line="Icon=$ICON"
    fi
    rm -f "$ICON.dl.png" "$ICON.tmp.png"
    cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Genki Arcade
Comment=Play and capture through the GENKI ShadowCast
Exec=$SCRIPT_DIR/genki-arcade.sh
$icon_line
Terminal=false
Categories=Game;Video;
EOF
    echo "    Added \"Genki Arcade\" to Launch Program (opens $URL in Chromium app mode)."
    echo "    It uses its own Chromium profile: the first launch shows Chromium's terms"
    echo "    dialog, and the site asks for camera access once."
    ;;
remove)
    rm -f "$DESKTOP" "$ICON"
    rm -rf "$PROFILE" "$SCRIPT_DIR"
    ;;
*)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
