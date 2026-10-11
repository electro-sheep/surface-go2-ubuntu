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

step "Desktop: Portrait Panel (battery % instead of the 4G icon in portrait)"
ext_install_local portrait-panel@electro
ext_enable portrait-panel@electro
need_logout=1

if [[ -n ${CALENDAR_FIT:-} ]]; then
  step "Desktop: Calendar Menu Fit (experimental)"
  # Narrows the clock drop-down's notification column so it fits the screen in portrait.
  ext_install_local calendar-menu-fit@electro
  ext_enable calendar-menu-fit@electro
fi
