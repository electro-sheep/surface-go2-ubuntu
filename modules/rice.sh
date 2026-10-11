# rice: Catppuccin Mocha desktop. Floating Open Bar pill, always-visible dock, rounded windows,
# Burn My Windows effects, Search Light on Super+Space, Catppuccin terminal + prompt + fetch,
# and the `rice` command (menu, wallpapers, battery-saver effects toggle, restore).

RICE=$HOME/.local/share/rice

step "Rice: packages"
apt_install papirus-icon-theme bibata-cursor-theme fonts-inter fonts-jetbrains-mono \
  python3-pil gir1.2-gtop-2.0 gnome-shell-extension-manager curl unzip

step "Rice: backup of the current desktop (for 'rice restore')"
mkdir -p "$RICE/backup"
if [[ ! -f $RICE/backup/dconf-before-rice.ini ]]; then
  dconf dump / > "$RICE/backup/dconf-before-rice.ini"
  cp ~/.bashrc "$RICE/backup/bashrc.before-rice"
  ok "saved to $RICE/backup"
else
  ok "a backup already exists, keeping it"
fi

step "Rice: adw-gtk3 theme (libadwaita look for GTK3 apps)"
if [[ ! -d ~/.local/share/themes/adw-gtk3-dark ]]; then
  url=$(curl -fsSL https://api.github.com/repos/lassekongo83/adw-gtk3/releases/latest \
        | python3 -I -c 'import json,sys; print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".tar.xz")))')
  mkdir -p ~/.local/share/themes
  curl -fsSL "$url" | tar -xJ -C ~/.local/share/themes
fi
ok "$(ls ~/.local/share/themes | tr '\n' ' ')"

step "Rice: Papirus-Dark-Mauve icons (violet folders, user-level copy)"
mauve=~/.local/share/icons/Papirus-Dark-Mauve
rm -rf "$mauve"; mkdir -p "$mauve"
sed -e 's/^Name=.*/Name=Papirus-Dark-Mauve/' -e 's/^Comment=.*/Comment=Papirus icon theme/' \
    -e 's/^Inherits=.*/Inherits=Papirus-Dark,Papirus,breeze-dark,hicolor/' \
    /usr/share/icons/Papirus-Dark/index.theme > "$mauve/index.theme"
# Every Papirus folder icon is a link to its blue variant; point ours at the violet one instead.
for dir in /usr/share/icons/Papirus-Dark/*/places; do
  rel=${dir#/usr/share/icons/Papirus-Dark/}
  for link in "$dir"/*.svg; do
    [[ -L $link ]] || continue
    target=$(readlink "$link")
    [[ $target == *-blue* ]] || continue
    violet=$dir/${target//-blue/-violet}
    [[ -e $violet ]] || continue
    mkdir -p "$mauve/$rel"
    ln -sf "$violet" "$mauve/$rel/$(basename "$link")"
  done
done
gtk-update-icon-cache -q "$mauve" 2>/dev/null || true
ok "$(find "$mauve" -type l | wc -l) folder icons re-pointed to violet"

step "Rice: app colours (GTK3 + GTK4/libadwaita)"
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
install -m 644 "$FILES/rice/gtk3.css" ~/.config/gtk-3.0/gtk.css
install -m 644 "$FILES/rice/catppuccin-mocha.css" ~/.config/gtk-4.0/gtk.css
ok "installed"

step "Rice: GNOME Shell extensions (extensions.gnome.org, GNOME $SHELL_VERSION)"
RICE_EXTS=(openbar@neuromorph just-perfection-desktop@just-perfection blur-my-shell@aunetx
  burn-my-windows@schneegans.github.com rounded-window-corners@fxgn search-light@icedman.github.com
  clipboard-indicator@tudmotu.com quick@web.search monitor@astraext.github.io)
for e in "${RICE_EXTS[@]}"; do
  ext_install_ego "$e" && ext_enable "$e"
done
need_logout=1

step "Rice: Catppuccin Mocha terminal profile"
uuid=6a1e83b5-79d2-4646-aab9-1264ef6fd602
dconf load "/org/gnome/terminal/legacy/profiles:/:$uuid/" < "$FILES/rice/terminal-profile.dconf"
list=$(gsettings get org.gnome.Terminal.ProfilesList list)
if [[ $list != *$uuid* ]]; then
  list=$(python3 -I -c 'import ast,sys; l=ast.literal_eval(sys.argv[1].replace("@as ","")); l.append(sys.argv[2]); print(l)' "$list" "$uuid")
  gsettings set org.gnome.Terminal.ProfilesList list "$list"
fi
gsettings set org.gnome.Terminal.ProfilesList default "$uuid"
ok "default profile: Catppuccin Mocha"

step "Rice: scripts, prompt and fetch"
mkdir -p ~/.local/bin ~/.config/rice "$RICE"
install -m 755 "$FILES/rice/rice" "$FILES/rice/rice-fetch" ~/.local/bin/
install -m 755 "$FILES/rice/apply.sh" "$RICE/"
install -m 644 "$FILES/rice/wallpaper.py" "$FILES/rice/catppuccin-mocha.css" "$RICE/"
echo "$uuid" > "$RICE/terminal-profile-uuid"
install -m 644 "$FILES/rice/shell.bash" ~/.config/rice/
grep -q '# >>> rice >>>' ~/.bashrc || \
  printf '\n# >>> rice >>>\n[ -f ~/.config/rice/shell.bash ] && . ~/.config/rice/shell.bash\n# <<< rice <<<\n' >> ~/.bashrc
ok "rice, rice-fetch, prompt hook in ~/.bashrc"

step "Rice: wallpaper"
mkdir -p ~/Pictures/Wallpapers
(cd /tmp && python3 -I "$RICE/wallpaper.py" 1920x1280 ~/Pictures/Wallpapers/catppuccin-mocha-waves.png 46)

step "Rice: apply all settings"
"$RICE/apply.sh" | sed 's/^/   /'
