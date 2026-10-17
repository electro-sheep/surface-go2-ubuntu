# Shared helpers, sourced by install.sh and every module.

REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
FILES=$REPO/files
EXT_DIR=$HOME/.local/share/gnome-shell/extensions
SHELL_VERSION=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)

c() { printf '\e[%sm' "$1"; }
step() { printf '\n%s==> %s%s\n' "$(c '1;35')" "$*" "$(c 0)"; }
info() { printf '   %s\n' "$*"; }
ok()   { printf '   %s✔%s %s\n' "$(c 32)" "$(c 0)" "$*"; }
warn() { printf '   %s!%s %s\n' "$(c 33)" "$(c 0)" "$*"; }
die()  { printf '%s✘ %s%s\n' "$(c 31)" "$*" "$(c 0)" >&2; exit 1; }

apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }

# A fresh install's /usr/sbin/policy-rc.d makes invoke-rc.d refuse to start or restart services,
# so packages installed afterwards come up half-configured. Remove it before installing anything.
remove_installer_policy_rc() {
  local f=/usr/sbin/policy-rc.d
  [[ -f $f ]] || return 0
  if grep -q 'exit 101' "$f" && ! dpkg -S "$f" >/dev/null 2>&1; then
    sudo rm -f "$f" && ok "removed the installer's leftover $f (it blocked service restarts)"
  else
    warn "$f exists and isn't the installer leftover; leaving it alone"
  fi
}

# Comment out the installer USB ("cdrom") apt source, which makes apt-get update fail.
fix_cdrom_source() {
  local f
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [[ -f $f ]] && grep -qE '^deb .*file:/+cdrom' "$f" || continue
    sudo sed -i -E 's|^(deb .*file:/+cdrom.*)|# \1|' "$f" && ok "disabled the cdrom apt source in $f"
  done
}

# Edit org.gnome.shell enabled-extensions / disabled-extensions lists.
ext_enable()  { _ext_lists "$1" add; }
ext_disable() { _ext_lists "$1" remove; }
_ext_lists() {
  local uuid=$1 mode=$2 en dis
  en=$(gsettings get org.gnome.shell enabled-extensions)
  dis=$(gsettings get org.gnome.shell disabled-extensions)
  read -r en dis < <(python3 -I - "$uuid" "$mode" "$en" "$dis" <<'EOF'
import ast, sys
uuid, mode, en, dis = sys.argv[1:]
parse = lambda s: list(ast.literal_eval(s.replace('@as ', ''))) if s.strip() not in ('@as []', '[]') else []
en, dis = parse(en), parse(dis)
add, rem = (en, dis) if mode == 'add' else (dis, en)
if uuid not in add: add.append(uuid)
if uuid in rem: rem.remove(uuid)
print(repr(en).replace(' ', ''), repr(dis).replace(' ', ''))
EOF
)
  gsettings set org.gnome.shell enabled-extensions "$en"
  gsettings set org.gnome.shell disabled-extensions "$dis"
  # Takes effect at once for extensions the running shell already knows about;
  # newly installed ones load at the next login.
  if [[ $mode == add ]]; then gnome-extensions enable "$uuid" 2>/dev/null; else gnome-extensions disable "$uuid" 2>/dev/null; fi
  return 0
}

# Install an extension from extensions.gnome.org for the running GNOME Shell version.
ext_install_ego() {
  local uuid=$1 url tmp
  if [[ -f $EXT_DIR/$uuid/metadata.json ]]; then ok "$uuid already installed"; return 0; fi
  url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$SHELL_VERSION" \
        | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["download_url"])') \
    || { warn "no $uuid build for GNOME $SHELL_VERSION on extensions.gnome.org"; return 1; }
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/ext.zip" "https://extensions.gnome.org$url" || { rm -rf "$tmp"; warn "download of $uuid failed"; return 1; }
  gnome-extensions install --force "$tmp/ext.zip"
  rm -rf "$tmp"
  if [[ -d $EXT_DIR/$uuid/schemas && ! -f $EXT_DIR/$uuid/schemas/gschemas.compiled ]]; then
    glib-compile-schemas "$EXT_DIR/$uuid/schemas"
  fi
  ok "installed $uuid"
}

# Install one of this repo's own extensions (files/extensions/<uuid>).
ext_install_local() {
  local uuid=$1
  mkdir -p "$EXT_DIR"
  rm -rf "${EXT_DIR:?}/$uuid"
  cp -r "$FILES/extensions/$uuid" "$EXT_DIR/"
  ok "installed $uuid"
}

# Recent adw-gtk3 releases ship a GTK4 stylesheet (gtk-4.0/libadwaita.css) built on CSS custom
# properties, which GTK reads only from 4.16. On older GTK (24.04 had 4.14) every GTK4 app (Files,
# Snapshot, the portal, even mutter's X11 window frames) logs ~960 "Theme parser error" lines at
# start. Without it they use GTK's built-in Adwaita look, which adw-gtk3 copies anyway.
adw_gtk3_gtk4_unreadable() {  # prints the adw-gtk3 gtk-4.0 folders this GTK can't read
  local v
  v=$(dpkg-query -W -f '${Version}' libgtk-4-1 2>/dev/null) || return 0
  dpkg --compare-versions "$v" lt 4.16 || return 0
  compgen -G "$HOME/.local/share/themes/adw-gtk3*/gtk-4.0" || true
}
adw_gtk3_gtk4_off() {
  local d
  while read -r d; do
    [[ -n $d ]] || continue
    rm -rf "$d.disabled"
    mv "$d" "$d.disabled"
    ok "set aside ${d/#$HOME/\~} (GTK4 older than 4.16 can't read it)"
  done < <(adw_gtk3_gtk4_unreadable)
}

need_logout=0
need_reboot=0
