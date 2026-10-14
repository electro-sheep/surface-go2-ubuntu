# rotate: cameras that turn with the screen. Apps get "Front Camera" and "Back Camera" from
# surface-camera-rotate, which turns the picture to match the accelerometer and hands it to
# PipeWire through the small pw-camsrc helper. A camera only switches on while an app uses it.

step "Rotate: cameras that turn with the screen"
apt_install libpipewire-0.3-dev pkg-config gcc gstreamer1.0-libcamera gstreamer1.0-plugins-base \
  python3-gi gir1.2-gstreamer-1.0 iio-sensor-proxy
tmp=$(mktemp -d)
gcc -O2 -Wall -o "$tmp/pw-camsrc" "$FILES/camera-rotate/pw-camsrc.c" \
  $(pkg-config --cflags --libs libpipewire-0.3) -lpthread
install -D -m 755 "$tmp/pw-camsrc" ~/.local/bin/pw-camsrc
rm -rf "$tmp"
install -D -m 755 "$FILES/camera-rotate/surface-camera-rotate" ~/.local/bin/surface-camera-rotate
ok "pw-camsrc and surface-camera-rotate in ~/.local/bin"

# Apps would otherwise also list WirePlumber's own libcamera cameras, which don't turn.
mkdir -p ~/.config/wireplumber/main.lua.d
cat > ~/.config/wireplumber/main.lua.d/51-surface-rotate.lua <<'EOF'
-- surface-camera-rotate publishes the cameras instead, turned to match the screen.
-- Delete this file and restart wireplumber to get the plain libcamera cameras back.
libcamera_monitor.enabled = false
EOF
ok "WirePlumber's unrotated cameras hidden"

mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/surface-camera-bridge.service <<'EOF'
[Unit]
Description=Surface cameras that turn with the screen (switch on only while an app uses them)
After=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=%h/.local/bin/surface-camera-rotate
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
# leftovers of an earlier v4l2loopback attempt: PipeWire can't negotiate with the loopback
rm -f ~/.local/bin/surface-camera-rotate-toggle ~/.local/share/applications/surface-camera-rotate.desktop
for f in /etc/modprobe.d/v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf; do
  if grep -qs 'Surface Camera\|surface-camera' "$f"; then sudo rm -f "$f"; ok "removed old $f"; fi
done
systemctl --user daemon-reload
systemctl --user enable surface-camera-bridge 2>/dev/null
systemctl --user restart wireplumber surface-camera-bridge 2>/dev/null \
  && ok "running; apps now see \"Front Camera\" and \"Back Camera\"" \
  || warn "couldn't start it now; it starts at the next login"
info "Picture upside down in portrait? Add --swap to ExecStart in ~/.config/systemd/user/surface-camera-bridge.service"
