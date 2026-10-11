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
# one store in the app grid: hide App Center (still installed, so it can come back)
snapstore=/var/lib/snapd/desktop/applications/snap-store_snap-store.desktop
if [[ -f $snapstore ]]; then
  sed '/^NoDisplay=/d; /^\[Desktop Entry\]/a NoDisplay=true' "$snapstore" > ~/.local/share/applications/snap-store_snap-store.desktop
fi
ok "GNOME Software installed (in the app grid, not pinned to the dock), App Center hidden"

step "Desktop: Calendar Menu Fit (clock drop-down fits in portrait)"
# The drop-down is ~670px wide (Yaru's 29em notification column plus the calendar), wider than the
# 640px portrait screen, so it hung off the left edge. The extension's stylesheet narrows the
# notification column.
ext_install_local calendar-menu-fit@electro
ext_enable calendar-menu-fit@electro
