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
t "zram used readily (swappiness)"   bash -c "[ \$(cat /proc/sys/vm/swappiness) -ge 100 ]"
t "zram set to zstd (from next boot if it was busy)" \
                                     grep -q '^compression-algorithm *= *zstd' /etc/systemd/zram-generator.conf.d/surface.conf
t "system logs capped"               test -f /etc/systemd/journald.conf.d/size.conf
t "cloud-init removed"               bash -c "! dpkg -s cloud-init"
t "NetworkManager-wait-online off"   bash -c "! systemctl is-enabled -q NetworkManager-wait-online"
t "no boot splash"                   bash -c "! grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*\bsplash\b' /etc/default/grub"
t "VA-API H.264 decode"              bash -c "vainfo 2>/dev/null | grep -q VAProfileH264"
t "Firefox: AV1 off (GPU decodes VP9)" grep -q '"media.av1.enabled"' /etc/firefox/policies/policies.json

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

step "Camera rotation"
t "pw-camsrc + surface-camera-rotate installed" test -x "$HOME/.local/bin/pw-camsrc" -a -x "$HOME/.local/bin/surface-camera-rotate"
t "rotating cameras running"        systemctl --user is-active surface-camera-bridge
t "apps see Front and Back Camera"  bash -c "pw-cli ls Node | grep -q surface_front_camera && pw-cli ls Node | grep -q surface_back_camera"
t "unrotated cameras hidden"        test -f "$HOME/.config/wireplumber/main.lua.d/51-surface-rotate.lua"

step "LTE"
if lsusb -d 045e:09a5 >/dev/null 2>&1; then
  t "udev wake-up rule"              test -f /etc/udev/rules.d/78-surface-lte-fix.rules
  t "resume hook"                    test -x /usr/lib/systemd/system-sleep/surface-lte-fix
  t "boot NTB-size fix unit"         test -f /etc/systemd/system/surface-lte-fix.service
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
  t "window effects: glitch in, incinerate out" bash -c "grep -q glitch-enable-effect=true ~/.config/burn-my-windows/profiles/*1.conf && grep -q incinerate-enable-effect=true ~/.config/burn-my-windows/profiles/*2.conf"
fi

t "auto-rotate unlocked at login"      bash -c "test -f ~/.config/autostart/surface-autorotate.desktop && gsettings get org.gnome.settings-daemon.peripherals.touchscreen orientation-lock | grep -qx false"

step "Tweaks"
t "Firefox user.js: no AV1, tabs saved every 60 s, no telemetry" \
                                     python3 -I "$FILES/tweaks/firefox-userjs.py" check "$FILES/tweaks/firefox-user.js"
t "idle background services off"     bash -c "! systemctl is-active -q kerneloops cups-browsed"
t "adw-gtk3 GTK4 stylesheet off (GTK4 < 4.16 can't read it)" test -z "$(adw_gtk3_gtk4_unreadable)"
t "GNOME Software out of the Activities search" \
                                     bash -c "gsettings get org.gnome.desktop.search-providers disabled | grep -q \"'org.gnome.Software.desktop'\""
t "GNOME Software not started at login (dock opens it directly)" \
                                     bash -c "[ ! -f /usr/lib/systemd/user/gnome-software.service ] || { [ \"\$(systemctl --user is-enabled gnome-software.service 2>/dev/null)\" = masked ] && grep -q '^DBusActivatable=false' ~/.local/share/applications/org.gnome.Software.desktop; }"

step "Power"
t "PCI runtime PM on every device"   bash -c "! grep -qx on /sys/bus/pci/devices/*/power/control"
t "PCIe ASPM powersupersave"         grep -q '\[powersupersave\]' /sys/module/pcie_aspm/parameters/policy
t "power profile follows the charger" bash -c "[ \"\$(powerprofilesctl get)\" = \$( [ \$(cat /sys/class/power_supply/ACAD/online) = 1 ] && echo performance || echo power-saver) ]"
t "turbo off on battery, on with the charger" bash -c "[ \$(cat /sys/devices/system/cpu/intel_pstate/no_turbo) != \$(cat /sys/class/power_supply/ACAD/online) ]"
t "NMI watchdog off"                 bash -c "[ \$(cat /proc/sys/kernel/nmi_watchdog) = 0 ]"
t "Wi-Fi power save on"              bash -c "iw dev wlp1s0 get power_save | grep -q on"
t "LTE modem still awake (power/control=on)" bash -c "grep -l 09a5 /sys/bus/usb/devices/*/idProduct | xargs -I{} dirname {} | xargs -I{} cat {}/power/control | grep -qx on"

if [[ -x ~/.local/bin/usage-tracker ]]; then
  step "Tracker"
  t "usage-tracker recording"        systemctl --user is-active usage-tracker.service
  t "usage-tracker logs the power profile, turbo, EPP and CPU temp" python3 -I -c "import sqlite3,os; c=sqlite3.connect(\"file:\"+os.path.expanduser(\"~/.local/share/usage-tracker/usage.db\")+\"?mode=ro\",uri=True); assert c.execute(\"select profile is not null and temp is not null from sys order by ts desc limit 1\").fetchone()[0]"
fi

step "Result: $pass passed, $fail failed"
(( fail == 0 ))
