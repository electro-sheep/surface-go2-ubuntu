# system: clean up what the Ubuntu installer leaves behind and trim boot/RAM overhead.

step "System: apt sources and installer leftovers"
fix_cdrom_source
remove_installer_policy_rc
sudo apt-get update

step "System: zram swap (half of RAM, zstd)"
apt_install systemd-zram-generator
sudo install -m 644 "$FILES/system/zram-generator.conf" /etc/systemd/zram-generator.conf
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service || warn "zram starts on next boot"
zramctl | sed 's/^/   /'

step "System: remove cloud-init"
if dpkg -s cloud-init >/dev/null 2>&1; then
  sudo apt-get purge -y cloud-init
  sudo rm -rf /etc/cloud /var/lib/cloud
  ok "cloud-init purged"
else
  ok "cloud-init not installed"
fi

step "System: don't wait for the network at boot"
sudo systemctl disable --now NetworkManager-wait-online.service 2>/dev/null || true
ok "NetworkManager-wait-online disabled"

step "System: drop the boot splash"
if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*\bsplash\b' /etc/default/grub; then
  sudo sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/{s/\bsplash\b//; s/  +/ /g; s/=" /="/; s/ "$/"/}' /etc/default/grub
  sudo update-grub
fi
ok "$(grep ^GRUB_CMDLINE_LINUX_DEFAULT= /etc/default/grub)"

step "System: hardware video decode (VA-API)"
apt_install vainfo intel-media-va-driver
if vainfo 2>/dev/null | grep -q VAProfileH264; then
  ok "VA-API works ($(vainfo 2>/dev/null | grep -c 'VAEntrypointVLD') decode profiles)"
else
  warn "vainfo shows no H.264 decode; check 'vainfo' output"
fi
