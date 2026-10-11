#!/usr/bin/env bash
# Report what's working. Read-only apart from short test captures from each camera.
#   ./check.sh            everything
#   ./check.sh --quick    skip the camera captures
set -u
REPO=$(cd "$(dirname "$0")" && pwd)
. "$REPO/modules/common.sh"
pass=0 fail=0
t() {  # t "description" command...
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; pass=$((pass + 1)); else printf '   %s✘%s %s\n' "$(c 31)" "$(c 0)" "$d"; fail=$((fail + 1)); fi
}

step "Machine"
info "$(cat /sys/class/dmi/id/product_name 2>/dev/null) · $(. /etc/os-release; echo "$PRETTY_NAME") · kernel $(uname -r)"

step "System"
t "no cdrom apt source"              bash -c "! grep -rqsE '^deb .*file:/+cdrom' /etc/apt/sources.list /etc/apt/sources.list.d/"
t "no installer policy-rc.d"         test ! -e /usr/sbin/policy-rc.d
t "zram swap active"                 bash -c "swapon --show=NAME | grep -q zram"
t "cloud-init removed"               bash -c "! dpkg -s cloud-init"
t "NetworkManager-wait-online off"   bash -c "! systemctl is-enabled -q NetworkManager-wait-online"
t "no boot splash"                   bash -c "! grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*\bsplash\b' /etc/default/grub"
t "VA-API H.264 decode"              bash -c "vainfo 2>/dev/null | grep -q VAProfileH264"

step "Cameras"
t "libcamera + PipeWire plugin installed" dpkg -s libcamera-tools pipewire-libcamera
t "IPA tuning symlinks"              test -e /usr/share/libcamera/ipa/ipu3/ov5693.yaml -a -e /usr/share/libcamera/ipa/ipu3/ov8865.yaml
t "$USER in video group"             bash -c "id -nG | grep -qw video"
t "patched ov8865 (rear) loaded"     bash -c "modinfo -n ov8865 | grep -q updates/dkms && lsmod | grep -q '^ov8865'"
t "patched ov5693 (front) loaded"    bash -c "modinfo -n ov5693 | grep -q updates/dkms && lsmod | grep -q '^ov5693'"
if [[ ${1:-} != --quick ]] && command -v cam >/dev/null; then
  mapfile -t cams < <(cam -l 2>/dev/null | grep -oE "^[0-9]+: .*" )
  t "libcamera sees 2 cameras"       test "${#cams[@]}" -ge 2
  for line in "${cams[@]}"; do
    n=${line%%:*}
    for size in 1280x720 1920x1080; do
      t "camera $n (${line#*: }) 10 frames at $size" \
        bash -c "timeout 20 cam -c $n -C10 -s width=${size%x*},height=${size#*x} 2>&1 | grep -c 'seq:' | grep -qx 10"
    done
  done
  t "no ipu3-cio2 errors since boot" bash -c "! journalctl -k -b -q 2>/dev/null | grep -iE 'ipu3-cio2.*(payload length|frame sync error)'"
fi

step "LTE"
if lsusb -d 045e:09a5 >/dev/null 2>&1; then
  t "udev wake-up rule"              test -f /etc/udev/rules.d/78-surface-lte-fix.rules
  t "resume hook"                    test -x /usr/lib/systemd/system-sleep/surface-lte-fix
  t "ModemManager sees the modem"    bash -c "mmcli -L | grep -q /Modem/"
  t "SIM present"                    bash -c "mmcli -m any | grep -qE 'primary sim path: /'"
  mmcli -m any 2>/dev/null | grep -E 'operator name|state:|signal quality' | sed 's/^ */   /'
else
  info "no LTE modem on this model"
fi

step "Desktop"
t "Ubuntu Tiling Assistant off"      bash -c "! gnome-extensions info tiling-assistant@ubuntu.com | grep -q 'State: ACTIVE'"
t "GNOME edge snapping on"           bash -c "gsettings get org.gnome.mutter edge-tiling | grep -q true"
t "Portrait Panel enabled"           bash -c "gsettings get org.gnome.shell enabled-extensions | grep -q portrait-panel@electro"
t "GNOME Software installed"         dpkg -s gnome-software-plugin-snap
t "GNOME Software not autostarting"  grep -q "^Hidden=true" "$HOME/.config/autostart/org.gnome.Software.desktop"
if command -v rice >/dev/null || [[ -x ~/.local/bin/rice ]]; then
  t "rice installed"                 test -x "$HOME/.local/bin/rice"
  t "Open Bar active"                bash -c "gnome-extensions info openbar@neuromorph | grep -q 'State: ACTIVE'"
  t "Rice Style enabled"             bash -c "gsettings get org.gnome.shell enabled-extensions | grep -q rice-style@electro"
fi

step "Result: $pass passed, $fail failed"
(( fail == 0 ))
