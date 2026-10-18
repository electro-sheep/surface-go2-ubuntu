# desktop: GNOME fixes for using the Surface as a touch tablet.

step "Desktop: touch-friendly window snapping"
# Ubuntu's Tiling Assistant decides where a dragged window snaps from the *mouse cursor*, which
# a finger drag on Wayland never moves, so windows snap to whichever half the cursor was last
# near. GNOME's own edge snapping follows the finger: drag to an edge for half, to the top to
# maximise; Super+Left/Right/Up/Down still work.
for e in tiling-assistant@ubuntu.com tiling-assistant@leleat-on-github tilingshell@ferrarodomenico.com; do
  ext_disable "$e"
done
gsettings set org.gnome.mutter edge-tiling true
ok "Tiling Assistant off, GNOME edge snapping on"

step "Desktop: Portrait Panel (even top-bar icons, no 4G icon in portrait)"
ext_install_local portrait-panel@electro
ext_enable portrait-panel@electro
need_logout=1

step "Desktop: Power Button (screen off, music keeps playing)"
# The power button suspends, which stops music and drops Bluetooth headphones. With music playing
# the extension locks and turns the screen off instead, holds Power Saver until unlock, and
# suspends once the music has stopped for 5 minutes. Otherwise the button suspends as before; with
# the screen off it just wakes it.
ext_install_local power-button@electro
ext_enable power-button@electro
# the extension hands the button back to gnome-settings-daemon when nothing is playing; Ubuntu's
# default there is the power-off menu, so make that a plain suspend
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'suspend'
need_logout=1

step "Desktop: no automatic suspend while plugged in"
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
ok "on battery it still suspends when idle"

step "Desktop: GNOME Software instead of App Center"
# App Center's window can't shrink below 852x652, which is bigger than the screen at 2x scaling
# in both orientations (640x960 portrait, 960x640 landscape), so it hangs off the edges and can't
# maximise. GNOME Software (snaps and debs) shrinks to phone width.
apt_install gnome-software gnome-software-plugin-snap
# Tablet tuning: no background service from login (RAM, battery), no automatic update downloads
# (LTE data; Ubuntu's updater and snapd already handle updates), and debs over snaps when an app
# comes in both, as they start faster on the m3.
mkdir -p ~/.config/autostart ~/.local/share/applications
{ cat /etc/xdg/autostart/org.gnome.Software.desktop; echo "Hidden=true"; } > ~/.config/autostart/org.gnome.Software.desktop
gsettings set org.gnome.software download-updates false
gsettings set org.gnome.software packaging-format-preference "['deb', 'snap']"
# no "Updates Available to Download" pop-ups: Ubuntu's Software Updater already announces updates
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/org-gnome-software/ enable false
# one store: uninstall App Center (`sudo snap install snap-store` brings it back), swap it for
# GNOME Software in the dock and open .deb files in GNOME Software instead
if snap list snap-store >/dev/null 2>&1; then
  sudo snap remove snap-store
fi
rm -f ~/.local/share/applications/snap-store_snap-store.desktop   # older versions only hid it
# in the dock, GNOME Software takes App Center's place (if App Center wasn't pinned, nothing is added)
favs=$(gsettings get org.gnome.shell favorite-apps)
favs=$(python3 -I - "$favs" <<'PY'
import ast, sys
favs = list(ast.literal_eval(sys.argv[1].replace('@as ', '')))
out = []
for a in favs:
    if a.startswith('snap-store_'):
        a = 'org.gnome.Software.desktop'
    if a not in out:
        out.append(a)
print(out)
PY
)
gsettings set org.gnome.shell favorite-apps "$favs"
xdg-mime default gnome-software-local-file-packagekit.desktop application/vnd.debian.binary-package
ok "GNOME Software installed and in App Center's place in the dock, App Center removed"

step "Desktop: Calendar Menu Fit (clock drop-down fits in portrait)"
# The drop-down is ~670px wide (Yaru's 29em notification column plus the calendar), wider than the
# 640px portrait screen, so it hung off the left edge. The extension's stylesheet narrows the
# notification column.
ext_install_local calendar-menu-fit@electro
ext_enable calendar-menu-fit@electro

step "Desktop: auto-rotate on at every login"
# The rotation lock survives reboots; a locked screen at boot is never what a tablet wants.
mkdir -p ~/.config/autostart
install -m644 "$FILES/desktop/surface-autorotate.desktop" ~/.config/autostart/surface-autorotate.desktop
gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock false
ok "rotation unlocked now and at each login"
