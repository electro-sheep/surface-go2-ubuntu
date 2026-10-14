#!/usr/bin/env bash
# check.sh — improvements: show DKMS status and build logs on failures; use test helper where available
set -u
REPO=$(cd "$(dirname "$0")" && pwd)
. "$REPO/modules/common.sh"
pass=0 fail=0

# helper test function
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
t "zram used readily (swappiness)"   bash -c "[ $(cat /proc/sys/vm/swappiness) -ge 100 ]"
t "system logs capped"               test -f /etc/systemd/journald.conf.d/size.conf
t "cloud-init removed"               bash -c "! dpkg -s cloud-init"
t "NetworkManager-wait-online off"   bash -c "! systemctl is-enabled -q NetworkManager-wait-online"
t "no boot splash"                   bash -c "! grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*\bsplash\b' /etc/default/grub"
t "VA-API H.264 decode"              bash -c "vainfo 2>/dev/null | grep -q VAProfileH264"
t "Firefox: AV1 off (GPU decodes VP9)" grep -q '"media.av1.enabled"' /etc/firefox/policies/policies.json

step "Cameras"
t "libcamera + PipeWire plugin installed" dpkg -s libcamera-tools pipewire-libcamera
nt "IPA tuning symlinks"              test -e /usr/share/libcamera/ipa/ipu3/ov5693.yaml -a -e /usr/share/libcamera/ipa/ipu3/ov8865.yaml
t "$USER in video group"             bash -c "id -nG | grep -qw video"

# Check DKMS-modified modules are present; show help if they aren't
if ! (modinfo -n ov8865 2>/dev/null | grep -q updates/dkms) || ! lsmod | grep -q '^ov8865'; then
  printf '   %s✘%s %s\n' "$(c 31)" "$(c 0)" "patched ov8865 (rear) loaded"
  echo "== DKMS status =="
  dkms status | sed 's/^/   /'
  echo "== Last DKMS build logs (tail up to 200 lines) =="
  sudo --non-interactive bash -c 'for f in /var/lib/dkms/*/*/build/make.log; do echo "--- $f"; tail -n 200 "$f"; done'
  fail=$((fail+1))
else
  ok "patched ov8865 (rear) loaded"
fi

if ! (modinfo -n ov5693 2>/dev/null | grep -q updates/dkms) || ! lsmod | grep -q '^ov5693'; then
  printf '   %s✘%s %s\n' "$(c 31)" "$(c 0)" "patched ov5693 (front) loaded"
  echo "== DKMS status =="
  dkms status | sed 's/^/   /'
  echo "== Last DKMS build logs (tail up to 200 lines) =="
  sudo --non-interactive bash -c 'for f in /var/lib/dkms/*/*/build/make.log; do echo "--- $f"; tail -n 200 "$f"; done'
  fail=$((fail+1))
else
  ok "patched ov5693 (front) loaded"
fi

if [[ ${1:-} != --quick ]] && command -v cam >/dev/null; then
  mapfile -t cams < <(cam -l 2>/dev/null | grep -oE "^[0-9]+: .*" )
  t "libcamera sees 2 cameras"       test "${#cams[@]}" -ge 2
  for line in "${cams[@]}"; do
    n=${line%%:*}
    for size in 1280x720 1920x1080; do
      # use the helper if available
      if [[ -x "$REPO/files/dkms/test-camera-stream.sh" ]]; then
        t "camera $n (${line#*: }) 10 frames at $size" bash -c "$REPO/files/dkms/test-camera-stream.sh -c $n -f 10 -s $size"
      else
        t "camera $n (${line#*: }) 10 frames at $size" \
          bash -c "timeout 20 cam -c $n -C10 -s width=${size%x*},height=${size#*x} 2>&1 | grep -c 'seq:' | grep -qx 10"
      fi
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
t "Calendar Menu Fit enabled"        bash -c "gsettings get org.gnome.shell enabled-extensions | grep -q calendar-menu-fit@electro"
t "Power Button enabled"             bash -c "gsettings get org.gnome.shell enabled-extensions | grep -q power-button@electro"
t "power button suspends"            bash -c "gsettings get org.gnome.settings-daemon.plugins.power power-button-action | grep -q suspend"
t "no idle suspend on AC"            bash -c "gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type | grep -q nothing"
t "GNOME Software installed"         dpkg -s gnome-software-plugin-snap
t "GNOME Software not autostarting"  grep -q "^Hidden=true" "$HOME/.config/autostart/org.gnome.Software.desktop"
t "App Center removed"               bash -c "! snap list snap-store"
t "App Center not in the dock"       bash -c "! gsettings get org.gnome.shell favorite-apps | grep -q snap-store"
if command -v rice >/dev/null || [[ -x ~/.local/bin/rice ]]; then
  t "rice installed"                 test -x "$HOME/.local/bin/rice"
  t "Open Bar active"                bash -c "gnome-extensions info openbar@neuromorph | grep -q 'State: ACTIVE'"
  t "Rice Style enabled"             bash -c "gsettings get org.gnome.shell enabled-extensions | grep -q rice-style@electro"
  t "Effects auto-switch running"    systemctl --user is-active rice-effects-auto.service
  t "window effects: glitch in, incinerate out" bash -c "grep -q glitch-enable-effect=true ~/.config/burn-my-windows/profiles/*1.conf && grep -q incinerate-enable-effect=true ~/.config/burn-my-win[...]"
fi

if [[ -x ~/.local/bin/usage-tracker ]]; then
  step "Tracker"
  t "usage-tracker recording"        systemctl --user is-active usage-tracker.service
fi

step "Result: $pass passed, $fail failed"
(( fail == 0 ))
