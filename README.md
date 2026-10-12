# Surface Go 2 on Ubuntu 24.04

Fixes for a fresh Ubuntu 24.04 install on a Microsoft Surface Go 2, on the **stock Ubuntu HWE kernel
(7.0)**, with no linux-surface kernel needed. Run one script after installing Ubuntu and you get working front
and rear cameras, LTE that survives suspend, a lighter system and touch-friendly window snapping.
There's also an optional Catppuccin desktop theme ("rice").

Everything here was worked out and tested on a real Surface Go 2 (Intel, 8 GB, LTE).

## Quick start

On the fresh install, connected to Wi-Fi, open a terminal and paste:

```bash
wget -qO- https://raw.githubusercontent.com/electro-sheep/surface-go2-ubuntu/main/bootstrap.sh | bash
```

It downloads the repo to `~/surface-go2-ubuntu` and installs everything: the fixes and the rice.
Then reboot, and run `~/surface-go2-ubuntu/check.sh` to see what's working.

**On any other computer** (Ubuntu 24.04 with the standard GNOME desktop), the same line installs
just the rice, as the other fixes are for the Surface's hardware.

To choose the modules, put them after `bash -s --` (here: the fixes without the rice):

```bash
wget -qO- https://raw.githubusercontent.com/electro-sheep/surface-go2-ubuntu/main/bootstrap.sh | bash -s -- system cameras lte desktop
```

Run it as your normal user, not with `sudo`. It asks for your password once. Running it again is
safe: it updates the download and each step checks what's already done.

Or by hand:

```bash
sudo apt install -y git
git clone https://github.com/electro-sheep/surface-go2-ubuntu.git
cd surface-go2-ubuntu
./install.sh          # the fixes
./install.sh rice     # optional: the themed desktop
sudo reboot
./check.sh            # after the reboot: shows what's working
```

## What it fixes

| Module | Problem on a fresh install | Fix |
|---|---|---|
| `system` | `apt update` fails on a leftover `file:///cdrom` source | comments it out |
| | the installer leaves `/usr/sbin/policy-rc.d`, which stops services from starting or restarting | removes it (only if no package owns it) |
| | 8 GB RAM and no compressed swap | zram swap: half of RAM, zstd, used readily (`swappiness` 150, no swap read-ahead) |
| | system logs grow past 400 MB | caps the journal at 200 MB |
| | cloud-init and NetworkManager-wait-online slow down boot | purges cloud-init, disables wait-online |
| | boot splash | drops `splash` from the GRUB command line |
| | | installs `vainfo` + `intel-media-va-driver` and checks hardware video decode |
| `cameras` | the kernel finds the cameras but apps can't use them | libcamera, PipeWire libcamera plugin, `uncalibrated.yaml` tuning symlinks for ov5693/ov8865, `video` group |
| | **rear and front cameras freeze after 1 frame** when an app picks 720p/480p or switches resolution (`ipu3-cio2 payload length` / `frame sync error`) | DKMS package `surface-go2-cameras` with both sensor drivers patched to program the mode on every stream start. Rebuilds itself on kernel updates |
| `lte` | the modem ignores MBIM, so there's no SIM | udev rule that makes `cdc_ncm` re-send the NTB size before ModemManager probes |
| | SIM disappears after suspend | `system-sleep` hook that does the same on resume |
| | modem is mapped to the empty eSIM | maps it to the physical SIM slot (`mbimcli --ms-set-device-slot-mappings=0`) |
| `desktop` | touch-dragging a window snaps it to whichever half the **mouse cursor** was last near | turns off Ubuntu's Tiling Assistant, so GNOME's own snapping (which follows your finger) is used |
| | App Center won't shrink below 852×652, bigger than the screen at 2×, so it hangs off the edges and can't maximise | installs **GNOME Software** (fits phone width) for snaps and debs, uninstalls App Center and puts GNOME Software in its place in the dock (`sudo snap install snap-store` brings App Center back); no background service, auto-downloads or update pop-ups (Software Updater still announces updates), debs preferred |
| | in portrait, the clock's calendar drop-down (~670px) is wider than the screen (640px) and hangs off the left | **Calendar Menu Fit** extension: narrows its notification column to 300px |
| | in portrait, the top-bar icons are cramped and run into the bar's rounded edge; apps open at landscape sizes | **Portrait Panel** extension: in portrait only, hides the 4G icon, gives the icons one even gap and opens new app windows maximised (on a portrait screen only, so an external monitor behaves normally) |
| | the power button always suspends, so music stops and Bluetooth headphones disconnect | **Power Button** extension: with music playing it locks and turns the screen off and the music keeps going, with Power Saver held until you unlock (the lock also unloads most extensions); 5 minutes after the music stops it suspends. With nothing playing it suspends (not Ubuntu's power-off menu), and with the screen off it just wakes it |

Optional modules:

- `rice`: Catppuccin Mocha desktop (see below).
- `sms`: Chatty ("Chats") for texting over the SIM. The modem can't do voice calls.

## Options

```bash
./install.sh --help
./install.sh cameras lte                 # just some modules
./install.sh all                         # fixes + rice

# create the mobile-data connection too (example: giffgaff UK)
APN=giffgaff.com APN_USER=giffgaff APN_PASS=password APN_NAME=giffgaff ./install.sh lte

```

Without `APN=…` you can add mobile data in **Settings → Mobile Network**.

## The rice

`./install.sh rice` installs:

- **Top bar:** floating Open Bar pill in Catppuccin Mocha with a mauve hairline, CPU/RAM graph on the left (updating every 3–5 s to spare the battery) and a clipboard menu. Menus and notifications are solid with rounded corners (Blur My Shell's pop-up blur is off, as it can't round its corners on GNOME 46).
- **Overview:** search bar tinted to match the bar and dock, via the small **Rice Style** extension.
- **Dock:** always visible, same colours as the bar, mauve running dots.
- **Windows:** 12 px rounded corners. Burn My Windows glitches windows in and burns them away (Incinerate) on close.
- **Battery:** blur, window effects and rounded corners switch off by themselves on battery or in Power Saver and come back when charging (`rice effects on|off|auto`).
- **Super+Space:** Search Light (Spotlight-style).
- **Look:** adw-gtk3-dark, Papirus folders recoloured violet, Bibata cursor, Inter and JetBrains Mono, and a Catppuccin GTK colour override.
- **Terminal:** solid Catppuccin profile, two-line prompt with git branch and error code, and a cat fetch on new tabs that moves the cat above the info when the window is narrow.
- **`rice` command:** `rice` (menu), `rice wall` (new generated wallpaper), `rice effects on|off|auto`, `rice status`, `rice apply`, `rice restore` (back to stock, using the backup taken at install).

Log out and back in once afterwards so GNOME loads the new extensions.

Sizes are tuned for the Go 2's 10.5" screen at 200% scale. The bar is 32 px, because Just Perfection
measures height in physical pixels (64 max). See the comments in `files/rice/apply.sh`.

## Repo layout

```
bootstrap.sh               the one-line installer: downloads the repo, runs install.sh
install.sh                 entry point
check.sh                   health check (./check.sh --quick skips camera captures)
modules/*.sh               one file per module
files/dkms/                patched ov5693/ov8865 sources + the .patch files + dkms.conf
files/lte/                 udev rule + system-sleep hook
files/system/              zram, sysctl and journald config
files/extensions/          Portrait Panel, Calendar Menu Fit, Power Button, Rice Style
files/rice/                theme scripts, CSS, terminal profile, wallpaper generator
```

## Notes and gotchas

- **Reboot after the camera module.** Don't `rmmod`/`modprobe` the sensor drivers live: they drop
  out of the IPU3 camera graph until the next boot.
- **The first frame from a sensor is garbage.** Capture ~10 frames and keep the last one.
- **Don't set up a v4l2loopback bridge** unless an app really needs it. It holds the camera
  exclusively and breaks PipeWire apps (Snapshot, Firefox, GNOME).
- **Kernel updates:** DKMS rebuilds the camera fix for every 7.0.x kernel. The sources are the
  v7.0 drivers, so `dkms.conf` only builds for `7.0.*`. When Ubuntu moves to a new kernel series,
  copy `drivers/media/i2c/ov8865.c` and `ov5693.c` from that kernel into `files/dkms/…/`, apply the
  two `.patch` files, bump the regex and re-run `./install.sh cameras`. Until then the stock drivers
  are used, so the cameras work but can freeze when an app changes resolution.
- The fix mirrors the upstream proposal *"media: ov8865: Program the sensor on stream start"* and
  [linux-surface PR #2169](https://github.com/linux-surface/linux-surface/pull/2169). Drop it once
  that lands in Ubuntu's kernel.
- The IR (Windows Hello) camera isn't supported on Linux.
- Ignore `deferred probe pending` messages in `dmesg`; they resolve themselves.

## License

GPL-2.0. The camera driver sources are from the Linux kernel (GPL-2.0).
