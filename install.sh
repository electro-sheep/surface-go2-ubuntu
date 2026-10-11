#!/usr/bin/env bash
# Surface Go 2 + Ubuntu 24.04 (stock HWE kernel) post-install fixes.
#
#   ./install.sh                 system + cameras + lte + desktop (the fixes)
#   ./install.sh all             the fixes + the Catppuccin "rice" desktop theme
#   ./install.sh <module>...     just the named modules, in the order given
#
# Modules:
#   system    apt cdrom source, installer policy-rc.d, zram, no cloud-init,
#             no NetworkManager-wait-online, no boot splash, VA-API check
#   cameras   libcamera userspace + IPA tuning symlinks + patched sensor drivers (DKMS)
#   lte       LTE modem wake-up fix (udev + resume hook), physical SIM slot, optional APN
#   desktop   touch-friendly window snapping, Portrait Panel extension
#   rice      Catppuccin Mocha desktop theme, terminal, prompt, fetch and the `rice` command
#   sms       Chatty (texting over the SIM)
#
# Options (environment variables):
#   APN=giffgaff.com APN_USER=giffgaff APN_PASS=password APN_NAME=giffgaff ./install.sh lte
#   CALENDAR_FIT=1 ./install.sh desktop   also enable the (experimental) Calendar Menu Fit extension
#   FORCE=1                               skip the "is this a Surface Go 2?" check
set -euo pipefail
[[ ${1:-} == -h || ${1:-} == --help ]] && { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
REPO=$(cd "$(dirname "$0")" && pwd)
export REPO
. "$REPO/modules/common.sh"

[[ $EUID -ne 0 ]] || die "run this as your normal user, not with sudo; it asks for your password when it needs it"
grep -q 'VERSION_ID="24.04"' /etc/os-release || warn "written for Ubuntu 24.04; this is $(. /etc/os-release; echo "$PRETTY_NAME")"
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [[ $product != "Surface Go 2" && -z ${FORCE:-} ]]; then
  die "this is a '$product', not a Surface Go 2 (set FORCE=1 to run anyway)"
fi

modules=("$@")
[[ ${#modules[@]} -gt 0 ]] || modules=(system cameras lte desktop)
[[ ${modules[*]} == all ]] && modules=(system cameras lte desktop rice)

for m in "${modules[@]}"; do
  [[ -f $REPO/modules/$m.sh ]] || die "unknown module '$m' (see ./install.sh --help)"
done

sudo -v   # ask for the password once, up front
for m in "${modules[@]}"; do
  . "$REPO/modules/$m.sh"
done

step "Done: ${modules[*]}"
(( need_reboot )) && warn "REBOOT to load the camera drivers (don't hot-reload them: they drop out of the camera graph)."
(( need_logout && ! need_reboot )) && warn "Log out and back in so GNOME loads the new extensions."
info "Run ./check.sh any time to see what's working."
