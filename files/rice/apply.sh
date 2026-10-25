#!/usr/bin/env bash
# rice/apply.sh — Catppuccin Mocha rice for GNOME 46 (Surface Go 2, 2x scale)
# Rebuilt from the desktop-setup notes: floating Open Bar pill, floating dock,
# Just Perfection trims, rounded windows, Burn My Windows effects, Search Light.
set -u
EXT=~/.local/share/gnome-shell/extensions

# gs <ext-dir> <schema> <key> <value>
gs() { gsettings --schemadir "$EXT/$1/schemas" set "$2" "$3" "$4" || echo "  ! failed: $2 $3"; }

# Catppuccin Mocha as Open Bar float triplets
BASE="['0.118', '0.118', '0.180']"
MANTLE="['0.094', '0.094', '0.145']"
CRUST="['0.067', '0.067', '0.106']"
SURFACE0="['0.192', '0.196', '0.267']"
TEXT="['0.804', '0.839', '0.957']"
MAUVE="['0.796', '0.651', '0.969']"
PINK="['0.961', '0.761', '0.906']"
RED="['0.953', '0.545', '0.659']"
GREEN="['0.651', '0.890', '0.631']"
YELLOW="['0.976', '0.886', '0.686']"

# Sizes, scaled down from the notes for a 960x640 logical screen
# RICE_VARIANT=touch (default): finger-sized bar and dock for the 10" touchscreen.
# RICE_VARIANT=compact: the original 24.04 sizes, more room for windows.
if [[ ${RICE_VARIANT:-touch} == compact ]]; then
  BAR_H=32; BAR_MARGIN=6; BAR_RADIUS=16; DOCK_ICON=44; BAR_FONT='Inter Semi-Bold 14'; BAR_ICON=24
else
  BAR_H=40; BAR_MARGIN=6; BAR_RADIUS=20; DOCK_ICON=56; BAR_FONT='Inter Semi-Bold 15'; BAR_ICON=28
fi
# Just Perfection pins the panel actor height in *physical* px (max 64), so it must be
# BAR_H x the shell's UI scale or the bar gets clipped. Past 64 we hand the height to
# Open Bar alone (0), which only takes effect after a fresh login.
SCALE=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
        --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null \
        | grep -oE "'legacy-ui-scaling-factor': <[0-9]+>" | grep -oE '[0-9]+')
JP_PANEL=$(( BAR_H * ${SCALE:-1} )); (( JP_PANEL > 64 )) && JP_PANEL=0

echo "• Interface: theme, icons, cursor, fonts"
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark-Mauve'
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
gsettings set org.gnome.desktop.interface cursor-size 24
gsettings set org.gnome.desktop.interface font-name 'Inter 10'
gsettings set org.gnome.desktop.interface document-font-name 'Inter 10'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 10'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Bold 10'
gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface enable-hot-corners false

echo "• Open Bar: floating Catppuccin pill"
OB=(openbar@neuromorph org.gnome.shell.extensions.openbar)
gs "${OB[@]}" pause-reload true
for p in "" dark-; do
  gs "${OB[@]}" ${p}bgcolor "$BASE"
  gs "${OB[@]}" ${p}bcolor "$MAUVE"
  gs "${OB[@]}" ${p}fgcolor "$TEXT"
  gs "${OB[@]}" ${p}accent-color "$MAUVE"
  gs "${OB[@]}" ${p}hcolor "$MAUVE"
  gs "${OB[@]}" ${p}shcolor "$CRUST"
  gs "${OB[@]}" ${p}mbgcolor "$BASE"
  gs "${OB[@]}" ${p}mbcolor "$MAUVE"
  gs "${OB[@]}" ${p}mfgcolor "$TEXT"
  gs "${OB[@]}" ${p}mhcolor "$MAUVE"
  gs "${OB[@]}" ${p}mscolor "$MAUVE"
  gs "${OB[@]}" ${p}mshcolor "$CRUST"
  gs "${OB[@]}" ${p}smbgcolor "$SURFACE0"
  gs "${OB[@]}" ${p}dbgcolor "$BASE"
  gs "${OB[@]}" ${p}winbcolor "$MAUVE"
done
gs "${OB[@]}" bartype 'Floating'
gs "${OB[@]}" position 'Top'
gs "${OB[@]}" height "$BAR_H"
gs "${OB[@]}" margin "$BAR_MARGIN"
gs "${OB[@]}" bradius "$BAR_RADIUS"
gs "${OB[@]}" font "$BAR_FONT"
gs "${OB[@]}" auto-bgalpha false
gs "${OB[@]}" bgalpha 0.80
gs "${OB[@]}" bwidth 1.0
gs "${OB[@]}" balpha 0.30
gs "${OB[@]}" fgalpha 1.0
gs "${OB[@]}" autofg-bar false
gs "${OB[@]}" autofg-menu false
gs "${OB[@]}" autohg-bar false
gs "${OB[@]}" autohg-menu false
gs "${OB[@]}" halpha 0.25
gs "${OB[@]}" heffect false
gs "${OB[@]}" shadow true
gs "${OB[@]}" shalpha 0.30
gs "${OB[@]}" neon false
gs "${OB[@]}" gradient false
gs "${OB[@]}" candybar false
gs "${OB[@]}" accent-override true
gs "${OB[@]}" menustyle true
gs "${OB[@]}" mbgalpha 1.0
gs "${OB[@]}" mbalpha 0.25
gs "${OB[@]}" mfgalpha 1.0
gs "${OB[@]}" mhalpha 0.25
gs "${OB[@]}" msalpha 0.85
gs "${OB[@]}" mshalpha 0.20
gs "${OB[@]}" smbgalpha 0.95
gs "${OB[@]}" smbgoverride true
gs "${OB[@]}" menu-radius 20.0
gs "${OB[@]}" notif-radius 14.0
gs "${OB[@]}" qtoggle-radius 50.0
gs "${OB[@]}" apply-menu-shell true
gs "${OB[@]}" apply-menu-notif true
gs "${OB[@]}" apply-accent-shell true
gs "${OB[@]}" warning-color "$YELLOW"
gs "${OB[@]}" success-color "$GREEN"
gs "${OB[@]}" destruct-color "$RED"
# dock picks up the bar's colours + hairline border
gs "${OB[@]}" dashdock-style 'Default'  # Rice Style draws the dock (one rounded layer)
gs "${OB[@]}" dbgalpha 0.80
gs "${OB[@]}" dbradius 20.0
gs "${OB[@]}" disize "$DOCK_ICON"
gs "${OB[@]}" dborder true
gs "${OB[@]}" dshadow true
gs "${OB[@]}" pause-reload false
# flip the toggle to regenerate the stylesheet
cur=$(gsettings --schemadir "$EXT/openbar@neuromorph/schemas" get org.gnome.shell.extensions.openbar trigger-reload)
gs "${OB[@]}" trigger-reload "$([ "$cur" = true ] && echo false || echo true)"

echo "• Just Perfection: trims to match the bar"
JP=(just-perfection-desktop@just-perfection org.gnome.shell.extensions.just-perfection)
gs "${JP[@]}" activities-button false
gs "${JP[@]}" panel-size "$JP_PANEL"
gs "${JP[@]}" ripple-box false
gs "${JP[@]}" startup-status 0
gs "${JP[@]}" panel-icon-size "$BAR_ICON"
gs "${JP[@]}" panel-button-padding-size 8
gs "${JP[@]}" panel-indicator-padding-size 4
gs "${JP[@]}" workspace-switcher-should-show true
# Ubuntu Dock stands in for the overview dash; Just Perfection's "show dash" (on by default)
# brought GNOME's own back on GNOME 50, a second big dock above ours in the app grid.
gs "${JP[@]}" dash false

echo "• Ubuntu Dock: floating island, hides behind windows (Dock Handle shows it)"
D=org.gnome.shell.extensions.dash-to-dock
gsettings set $D dock-position 'BOTTOM'
gsettings set $D dash-max-icon-size "$DOCK_ICON"
gsettings set $D icon-size-fixed true
gsettings set $D extend-height false
gsettings set $D always-center-icons true
gsettings set $D dock-fixed false
gsettings set $D autohide true
gsettings set $D intellihide true
gsettings set $D intellihide-mode 'FOCUS_APPLICATION_WINDOWS'
gsettings set $D require-pressure-to-show true
gsettings set $D pressure-threshold 60.0
gsettings set $D show-delay 0.10
gsettings set $D hide-delay 0.25
gsettings set $D transparency-mode 'DEFAULT'
gsettings set $D background-opacity 0.80
gsettings set $D click-action 'minimize-or-previews'
gsettings set $D scroll-action 'cycle-windows'
gsettings set $D show-trash false
gsettings set $D show-mounts false
gsettings set $D apply-custom-theme false
gsettings set $D custom-theme-shrink true
gsettings set $D running-indicator-style 'DOTS'
gsettings set $D custom-theme-customize-running-dots true
gsettings set $D custom-theme-running-dots-color '#cba6f7'
gsettings set $D custom-theme-running-dots-border-color '#cba6f7'
gsettings set $D custom-theme-running-dots-border-width 0
gsettings set $D preferred-monitor -2
gsettings set $D multi-monitor false

echo "• Blur My Shell: overview/folders/lockscreen only (no square corners)"
B=blur-my-shell@aunetx; BS=org.gnome.shell.extensions.blur-my-shell
gs $B $BS.panel blur false
gs $B $BS.dash-to-dock blur false
gs $B $BS.overview blur true
gs $B $BS.appfolder blur true
gs $B $BS.lockscreen blur true
gs $B $BS.popup blur false   # its live blur can't round corners on GNOME 46

echo "• Rounded window corners: 12px, mauve hairline on focus"
R=(rounded-window-corners@fxgn org.gnome.shell.extensions.rounded-window-corners-reborn)
gs "${R[@]}" global-rounded-corner-settings "{'padding': <{'left': <uint32 1>, 'right': <uint32 1>, 'top': <uint32 1>, 'bottom': <uint32 1>}>, 'keepRoundedCorners': <{'maximized': <false>, 'fullscreen': <false>}>, 'borderRadius': <uint32 12>, 'smoothing': <0.4>, 'borderColor': <[0.796, 0.651, 0.969, 0.35]>, 'enabled': <true>}"
gs "${R[@]}" border-width 1
gs "${R[@]}" skip-libadwaita-app false
gs "${R[@]}" focused-shadow "{'horizontalOffset': 0, 'verticalOffset': 6, 'blurOffset': 24, 'spreadRadius': 2, 'opacity': 55}"
gs "${R[@]}" unfocused-shadow "{'horizontalOffset': 0, 'verticalOffset': 3, 'blurOffset': 12, 'spreadRadius': 1, 'opacity': 30}"

echo "• Search Light: Super+Space spotlight"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['XF86Keyboard']"
SL=(search-light@icedman.github.com org.gnome.shell.extensions.search-light)
gs "${SL[@]}" shortcut-search "['<Super>space']"
gs "${SL[@]}" background-color '(0.118, 0.118, 0.180, 0.88)'
gs "${SL[@]}" border-color '(0.796, 0.651, 0.969, 0.45)'
gs "${SL[@]}" border-thickness 1
gs "${SL[@]}" border-radius 16.0
gs "${SL[@]}" text-color '(0.804, 0.839, 0.957, 1.0)'
gs "${SL[@]}" entry-text-color '(0.804, 0.839, 0.957, 1.0)'
gs "${SL[@]}" blur-background true
gs "${SL[@]}" blur-brightness 0.5
gs "${SL[@]}" scale-width 0.55
gs "${SL[@]}" scale-height 0.55

echo "• Burn My Windows: glitch in, incinerate out"
P=~/.config/burn-my-windows/profiles
mkdir -p "$P"
rm -f "$P"/*.conf
cat > "$P/1000000000000001.conf" <<'EOF2'
[burn-my-windows-profile]
profile-animation-type=1
fire-enable-effect=false
glitch-enable-effect=true
EOF2
cat > "$P/1000000000000002.conf" <<'EOF2'
[burn-my-windows-profile]
profile-animation-type=2
fire-enable-effect=false
incinerate-enable-effect=true
EOF2

echo "• Astra Monitor: CPU + RAM only, mauve, left side of the bar"
AM=(monitor@astraext.github.io org.gnome.shell.extensions.astra-monitor)
gs "${AM[@]}" panel-box 'left'
gs "${AM[@]}" storage-header-show false
gs "${AM[@]}" network-header-show false
gs "${AM[@]}" sensors-header-show false
gs "${AM[@]}" gpu-header-show false
# slower polling: fewer CPU wake-ups and bar redraws on battery (hidden monitors slowest)
gs "${AM[@]}" processor-update 3.0
gs "${AM[@]}" memory-update 5.0
for m in storage network sensors gpu; do gs "${AM[@]}" $m-update 10.0; done
gs "${AM[@]}" processor-header-graph-width 28
# what shows in the bar: CPU = icon + graph, RAM = icon + bar, no numbers. Set every switch, so
# options changed on this machine before (percentages, say) can't make it look different.
for k in processor-header-icon processor-header-graph memory-header-icon memory-header-bars; do
  gs "${AM[@]}" $k true
done
for k in processor-header-percentage processor-header-percentage-core processor-header-bars \
         processor-header-bars-core processor-header-frequency memory-header-percentage \
         memory-header-value memory-header-free memory-header-graph compact-mode; do
  gs "${AM[@]}" $k false
done
gs "${AM[@]}" processor-header-icon-size "$BAR_ICON"
gs "${AM[@]}" memory-header-icon-size "$BAR_ICON"
gs "${AM[@]}" processor-header-graph-color1 'rgba(203,166,247,1.0)'
gs "${AM[@]}" processor-header-graph-color2 'rgba(245,194,231,1.0)'
gs "${AM[@]}" memory-header-bars-color1 'rgba(203,166,247,1.0)'
gs "${AM[@]}" memory-header-bars-color2 'rgba(203,166,247,0.3)'
gs "${AM[@]}" memory-used 'active'

echo "• Workspace Indicator: off (its previews overflow a 960px-wide bar)"
gnome-extensions disable workspace-indicator@gnome-shell-extensions.gcampax.github.com 2>/dev/null

echo "• Terminal: no menu bar, dark; Files: list view"
gsettings set org.gnome.Terminal.Legacy.Settings default-show-menubar false
gsettings set org.gnome.Terminal.Legacy.Settings theme-variant 'dark'
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'

echo "• Desktop icons: hidden for a clean wallpaper"
gsettings set org.gnome.shell.extensions.ding show-home false
gsettings set org.gnome.shell.extensions.ding show-trash false
gsettings set org.gnome.shell.extensions.ding show-volumes false

echo "• Wallpaper"
W=~/Pictures/Wallpapers/catppuccin-mocha-waves.png
gsettings set org.gnome.desktop.background picture-uri "file://$W"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$W"
gsettings set org.gnome.desktop.background picture-options 'zoom'
gsettings set org.gnome.desktop.screensaver picture-uri "file://$W"

echo "done."
