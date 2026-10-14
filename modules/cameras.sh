#!/usr/bin/env bash
# modules/cameras.sh (improved DKMS flow)
# Adds AUTO_DKMS=1 to run non-interactively and FORCE_DKMS=1 to force DKMS build on non-7.0 kernels.

step "Cameras: libcamera + PipeWire userspace"
# If AUTO_DKMS is set we run apt non-interactively for the DKMS step
if [[ ${AUTO_DKMS:-0} -eq 1 ]]; then
  export DEBIAN_FRONTEND=noninteractive
fi
apt_install libcamera-ipa libcamera-tools pipewire-libcamera gstreamer1.0-libcamera v4l-utils

# No tuning files ship for these sensors; the uncalibrated one works.
ipa=/usr/share/libcamera/ipa/ipu3
for s in ov5693 ov8865; do
  [[ -e $ipa/$s.yaml ]] || sudo ln -sf uncalibrated.yaml "$ipa/$s.yaml"
done
ok "IPA tuning: $(ls "$ipa" | tr '\n' ' ')"

# Without the video group, WirePlumber can start before logind grants the /dev/media* ACLs
# and end up with no cameras until it's restarted.
if ! id -nG "$USER" | grep -qw video; then
  sudo usermod -aG video "$USER"
  ok "added $USER to the video group"
  need_reboot=1
fi

step "Cameras: patched sensor drivers (DKMS package surface-go2-cameras)"
kver=$(uname -r)
pkg=surface-go2-cameras; ver=1.0

if [[ $kver =~ ^7\.0\. ]]; then
  # Expected kernel series — install DKMS normally
  apt_install dkms build-essential "linux-headers-$kver"
  # an earlier rear-camera-only version of this fix
  if dkms status ov8865-surface 2>/dev/null | grep -q .; then sudo dkms remove ov8865-surface/1.0 --all || true; fi
  sudo rm -rf /usr/src/ov8865-surface-1.0
  if dkms status "$pkg/$ver" 2>/dev/null | grep -q .; then sudo dkms remove "$pkg/$ver" --all; fi
  sudo rm -rf "/usr/src/$pkg-$ver"
  sudo cp -r "$FILES/dkms/$pkg-$ver" /usr/src/
  sudo dkms install "$pkg/$ver" -k "$kver" || { echo "DKMS install failed; see /var/lib/dkms/$pkg/$ver/build/make.log"; exit 1; }
  ok "$(dkms status "$pkg")"
  need_reboot=1
else
  warn "kernel $kver isn't 7.0.x; the bundled driver sources are from v7.0, so we normally skip DKMS."
  if [[ ${FORCE_DKMS:-0} -eq 1 ]]; then
    warn "FORCE_DKMS=1 set: attempting DKMS build on $kver (may fail)."
    apt_install dkms build-essential "linux-headers-$kver" || true
    if dkms status "$pkg/$ver" 2>/dev/null | grep -q .; then sudo dkms remove "$pkg/$ver" --all || true; fi
    sudo rm -rf "/usr/src/$pkg-$ver" || true
    sudo cp -r "$FILES/dkms/$pkg-$ver" /usr/src/ || true
    if ! sudo dkms install "$pkg/$ver" -k "$kver"; then
      echo "DKMS build failed for $kver. Inspect /var/lib/dkms/$pkg/$ver/build/make.log for details."
      warn "You can refresh the driver sources for this kernel series with scripts/update-dkms-sources.sh"
    else
      ok "DKMS installed for $kver"
      need_reboot=1
    fi
  else
    warn "Skipping DKMS: set FORCE_DKMS=1 to attempt a build on non-7.0 kernels (risky)."
  fi
fi

# Restart PipeWire/wireplumber so new drivers are picked up when possible
systemctl --user restart pipewire wireplumber 2>/dev/null || true
info "after the reboot: ./check.sh tests both cameras"
