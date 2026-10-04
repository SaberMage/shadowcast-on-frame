# shadowcast-on-frame

Make the **Genki ShadowCast** work on **Steam Frame**, along with other USB
capture cards and webcams.

Out of the box, the ShadowCast's **audio** works on Steam Frame but its
**video** doesn't: web apps like Genki Arcade (in Chromium) get sound but no
picture. Steam Frame's SteamOS kernel is built without USB video support
(`CONFIG_MEDIA_USB_SUPPORT` is off), so there's no `uvcvideo` driver and no
`/dev/video*` device for the capture card. The USB audio driver is built in,
which is why sound works.

This repo builds the standard Linux `uvcvideo` driver for your exact kernel,
loads it at every boot, and rebuilds it by itself after SteamOS updates. After
that, the ShadowCast appears as a normal camera (MJPEG up to 1080p60), and
anything that uses cameras can see it, including Chromium, Genki Arcade and
OBS.

## Install

In desktop mode (or over SSH):

```sh
git clone https://github.com/SaberMage/shadowcast-on-frame
cd shadowcast-on-frame
./install.sh
```

It asks for your `sudo` password once, near the end. If you've never set one
on the device, run `passwd` first. Then plug in the ShadowCast, if it isn't
already, and reload Genki Arcade.

**SteamOS updates are handled automatically.** If an update brings a new
kernel, the boot service notices there are no modules for it, waits for the
network, rebuilds and installs them, and loads them, usually within a minute
or two of booting. Progress and errors go to
`journalctl -u shadowcast-on-frame`. If a rebuild fails (for example, there
was no network at boot), reboot or run `./install.sh` again.

To remove everything, run `./uninstall.sh`.

## What it does

1. Finds your kernel package from `/usr/lib/modules/$(uname -r)/pkgbase`
   (for example `linux-618-deckard`), and downloads the exactly matching
   `…-headers` package from your own SteamOS package repositories.
2. Downloads the `uvcvideo` driver source from the upstream Linux release that
   matches your kernel (for example `v6.18`). It also fetches any helpers your
   kernel lacks: on SteamOS 0.3, `uvc` (shared UVC format tables) and
   `videobuf2-vmalloc`.
3. Builds them as your user, and checks they match your kernel's version
   string.
4. With `sudo`, installs them root-owned to
   `/srv/shadowcast-on-frame/<kernel version>/`, along with `build.sh` and
   `load.sh`, and enables `shadowcast-on-frame.service`. At every boot, the
   service runs `load.sh`. That loads the modules for the running kernel,
   first running the same build as root if that kernel doesn't have any yet,
   and removes builds for old kernels.

Where things go, and why:

- `/srv` lives on the persistent home partition. `/var` and the OS partitions
  are replaced by atomic SteamOS updates.
- Systemd services in `/etc/systemd/system` are on SteamOS's update keep-list,
  so the service survives updates.
- The modules are owned by root because a root boot service loads them. Loading
  kernel code from a user-writable folder would let any user process inject
  code into the kernel.
- Nothing is built or installed in `/usr`, and nothing touches the read-only OS
  image.

No compiled code is distributed here. The driver is GPL-2.0 Linux kernel code,
built from upstream sources on your device.

## Troubleshooting

- **Check whether the driver is loaded:** run `lsmod | grep uvc`, or
  `systemctl status shadowcast-on-frame`.
- **List capture devices:** `v4l2-ctl --list-devices`. The ShadowCast shows up
  as two nodes; the first is the video stream.
- **Grab a test frame:**
  `ffmpeg -f v4l2 -input_format mjpeg -video_size 1920x1080 -i /dev/video24 -frames:v 1 test.jpg`
  (use your device number).
- **"headers package … is X, but your kernel is Y":** the repositories have
  moved on to a newer kernel than the one you're running. Install the pending
  SteamOS update and reboot; the service rebuilds automatically.
- **Chromium doesn't list the camera:** reload the page, or restart Chromium,
  after the driver loads. The Chromium Flatpak already has device access.

Tested on Steam Frame, SteamOS 0.3.0 (kernel `6.18.0-gfbdbca41fd45`), with a
GENKI ShadowCast 3 (USB ID `32ed:3701`).

## License

MIT for the scripts in this repository. The driver sources that `install.sh`
downloads are part of the Linux kernel and are licensed GPL-2.0.
