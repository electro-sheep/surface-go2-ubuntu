# cameras: the stock kernel already finds the front (ov5693), rear (ov8865) and IR cameras;
# only userspace is missing, plus two driver bugs that stall streams after one frame.

step "Cameras: libcamera + PipeWire userspace"
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
# Both sensors only write their mode registers on runtime resume. The rear stays powered while
# PipeWire holds its focus motor (VCM device link), the front for its 1 s autosuspend delay, so a
# resolution change never reaches the sensor: "ipu3-cio2 payload length" / "frame sync error"
# and the stream stalls after one frame. The patches program the mode on every stream start.
kver=$(uname -r)
pkg=surface-go2-cameras; ver=1.0
if [[ ! $kver =~ ^7\.0\. ]]; then
  warn "kernel $kver isn't 7.0.x; the bundled driver sources are from v7.0, so skipping."
  warn "Refresh files/dkms/$pkg-$ver/*.c from that kernel's source and re-apply the .patch files."
else
  apt_install dkms build-essential "linux-headers-$kver"
  # an earlier rear-camera-only version of this fix
  if dkms status ov8865-surface 2>/dev/null | grep -q .; then sudo dkms remove ov8865-surface/1.0 --all || true; fi
  sudo rm -rf /usr/src/ov8865-surface-1.0
  if dkms status "$pkg/$ver" 2>/dev/null | grep -q .; then sudo dkms remove "$pkg/$ver" --all; fi
  sudo rm -rf "/usr/src/$pkg-$ver"
  sudo cp -r "$FILES/dkms/$pkg-$ver" /usr/src/
  sudo dkms install "$pkg/$ver" -k "$kver"
  ok "$(dkms status "$pkg")"
  need_reboot=1
fi

systemctl --user restart pipewire wireplumber 2>/dev/null || true
info "after the reboot: ./check.sh tests both cameras"
