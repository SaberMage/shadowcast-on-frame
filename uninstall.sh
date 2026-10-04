#!/bin/bash
# Removes what install.sh set up: the boot service, the built modules, and (if
# nothing is using them) unloads the driver.
set -uo pipefail
SERVICE=shadowcast-on-frame.service

sudo systemctl disable --now "$SERVICE" 2>/dev/null
sudo rm -f "/etc/systemd/system/$SERVICE"
sudo systemctl daemon-reload
for m in uvcvideo videobuf2_vmalloc uvc; do
    grep -q "^$m " /proc/modules && { sudo rmmod "$m" || echo "couldn't unload $m (in use?); it goes away at reboot"; }
done
sudo rm -rf /srv/shadowcast-on-frame
"$(dirname "$(readlink -f "$0")")/src/genki-arcade-launcher.sh" remove
echo "shadowcast-on-frame removed."
