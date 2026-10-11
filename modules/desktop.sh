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
# one store in the app grid: hide App Center (still installed, so it can come back)
snapstore=/var/lib/snapd/desktop/applications/snap-store_snap-store.desktop
if [[ -f $snapstore ]]; then
  sed '/^NoDisplay=/d; /^\[Desktop Entry\]/a NoDisplay=true' "$snapstore" > ~/.local/share/applications/snap-store_snap-store.desktop
fi
python3 -I - <<'PY'
import ast, subprocess
cur = subprocess.run(['gsettings', 'get', 'org.gnome.shell', 'favorite-apps'], capture_output=True, text=True).stdout.strip()
fav = list(ast.literal_eval(cur.replace('@as ', ''))) if cur not in ('@as []', '[]') else []
if 'org.gnome.Software.desktop' not in fav:
    subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'favorite-apps', str(fav + ['org.gnome.Software.desktop'])], check=True)
PY
ok "GNOME Software in the dock, App Center hidden"

if [[ -n ${CALENDAR_FIT:-} ]]; then
  step "Desktop: Calendar Menu Fit (experimental)"
  # Narrows the clock drop-down's notification column so it fits the screen in portrait.
  ext_install_local calendar-menu-fit@electro
  ext_enable calendar-menu-fit@electro
fi
