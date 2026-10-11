#!/usr/bin/env bash
# One-line install, from a terminal on the fresh machine:
#
#   wget -qO- https://raw.githubusercontent.com/electro-sheep/surface-go2-ubuntu/main/bootstrap.sh | bash
#
# Clones (or updates) the repo into ~/surface-go2-ubuntu and runs ./install.sh. On a Surface Go 2
# that's everything (the fixes + the rice); on any other machine, just the rice. To pick the
# modules yourself, put them after `bash -s --`:
#
#   wget -qO- https://raw.githubusercontent.com/electro-sheep/surface-go2-ubuntu/main/bootstrap.sh | bash -s -- rice
set -euo pipefail

main() {
  local url=https://github.com/electro-sheep/surface-go2-ubuntu.git
  local dir=${SG2_DIR:-$HOME/surface-go2-ubuntu}
  [[ $EUID -ne 0 ]] || { echo "run this as your normal user, not with sudo" >&2; exit 1; }

  if ! command -v git >/dev/null; then
    echo "==> Installing git"
    sudo apt-get install -y git || { sudo apt-get update || true; sudo apt-get install -y git; }
  fi

  if [[ -d $dir/.git ]]; then
    echo "==> Updating $dir"
    git -C "$dir" pull --ff-only
  else
    echo "==> Downloading to $dir"
    git clone --depth 1 "$url" "$dir"
  fi

  local modules=("$@")
  if [[ ${#modules[@]} -eq 0 ]]; then
    if [[ $(cat /sys/class/dmi/id/product_name 2>/dev/null) == "Surface Go 2" ]]; then
      modules=(all)
    else
      modules=(rice)
    fi
  fi
  "$dir/install.sh" "${modules[@]}"
}

# Piped into bash, stdin is this script; hand the installer the terminal instead. Calling main
# on the last line also means nothing runs if the download was cut short.
if [[ -t 0 ]]; then main "$@"; else main "$@" </dev/tty; fi
