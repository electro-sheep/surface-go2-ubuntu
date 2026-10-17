#!/usr/bin/env bash
# Surface Go 2 + Ubuntu 26.04 (stock HWE kernel) post-install fixes.
#
#   ./install.sh                 system + cameras + rotate + lte + desktop + tweaks (the fixes)
#   ./install.sh all             the fixes + the Catppuccin "rice" desktop theme
#   ./install.sh <module>...     just the named modules, in the order given
#
# Modules:
#   system    apt cdrom source, installer policy-rc.d, zram (used readily), log cap, no cloud-init,
#             no NetworkManager-wait-online, no boot splash, VA-API check
#   cameras   libcamera userspace + IPA tuning symlinks + patched sensor drivers (DKMS)
#   rotate    cameras that turn with the screen (apps see "Front Camera" / "Back Camera")
#   lte       LTE modem wake-up fix (udev + resume hook), physical SIM slot, optional APN
#   desktop   touch-friendly window snapping, Portrait Panel, Calendar Menu Fit, Power Button,
#             GNOME Software
#   tweaks    trims found with usage-tracker: Firefox user.js (no AV1, tabs saved every 60 s, no
#             telemetry), adw-gtk3's GTK4 stylesheet off on GTK < 4.16 (journal spam), GNOME
#             Software out of the Activities search (stays in RAM)
#   rice      Catppuccin Mocha desktop theme, terminal, prompt, fetch and the `rice` command
#             (works on any Ubuntu 26.04 GNOME machine, not just the Surface)
#   sms       Chatty (texting over the SIM)
#   tracker   usage-tracker: records which apps use the CPU, GPU, RAM and battery, in the
#             background, so you can see what to trim (any machine)
#
# Options (environment variables):
#   APN=giffgaff.com APN_USER=giffgaff APN_PASS=password APN_NAME=giffgaff ./install.sh lte
#   FORCE=1                               skip the "is this a Surface Go 2?" check
set -euo pipefail
[[ ${1:-} == -h || ${1:-} == --help ]] && { sed -n '2,/^set /{/^#/p}' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
REPO=$(cd "$(dirname "$0")" && pwd)
export REPO
. "$REPO/modules/common.sh"

[[ $EUID -ne 0 ]] || die "run this as your normal user, not with sudo; it asks for your password when it needs it"
grep -q 'VERSION_ID="26.04"' /etc/os-release || warn "written for Ubuntu 26.04; this is $(. /etc/os-release; echo "$PRETTY_NAME")"

modules=("$@")
[[ ${#modules[@]} -gt 0 ]] || modules=(system cameras rotate lte desktop tweaks)
[[ ${modules[*]} == all ]] && modules=(system cameras rotate lte desktop tweaks rice tracker)

for m in "${modules[@]}"; do
  [[ -f $REPO/modules/$m.sh ]] || die "unknown module '$m' (see ./install.sh --help)"
done

# The rice and the tracker run on any machine; the other modules are for the Go 2's hardware.
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
hardware=$(printf '%s\n' "${modules[@]}" | grep -vxE 'rice|tracker' || true)
if [[ $product != "Surface Go 2" && -z ${FORCE:-} && -n $hardware ]]; then
  die "this is a '$product', not a Surface Go 2; only the rice and tracker are for any machine: ./install.sh rice tracker (FORCE=1 runs the rest anyway)"
fi

# ask for the password once, up front (tracker and tweaks don't need it)
needs_sudo=$(printf '%s\n' "${modules[@]}" | grep -vxE 'tracker|tweaks' || true)
[[ -z $needs_sudo ]] || sudo -v
for m in "${modules[@]}"; do
  . "$REPO/modules/$m.sh"
done

step "Done: ${modules[*]}"
(( need_reboot )) && warn "REBOOT to load the camera drivers (don't hot-reload them: they drop out of the camera graph)."
(( need_logout && ! need_reboot )) && warn "Log out and back in so GNOME loads the new extensions."
info "Run ./check.sh any time to see what's working."
