# system: clean up what the Ubuntu installer leaves behind and trim boot/RAM overhead.

step "System: apt sources and installer leftovers"
fix_cdrom_source
remove_installer_policy_rc
sudo apt-get update

step "System: zram swap (half of RAM, zstd)"
apt_install systemd-zram-generator
# A drop-in, not /etc/systemd/zram-generator.conf: the 26.04 upgrade renamed that file to
# .dpkg-bak (the package stopped shipping it), which quietly put zram back on lzo-rle.
sudo install -D -m 644 "$FILES/system/zram-generator.conf" /etc/systemd/zram-generator.conf.d/surface.conf
sudo systemctl daemon-reload
zused=$(awk '{print $1}' /sys/block/zram0/mm_stat 2>/dev/null || echo 0)
if (( ${zused:-0} < 64 << 20 )); then
  sudo systemctl restart systemd-zram-setup@zram0.service || warn "zram starts on next boot"
elif [[ $(cat /sys/block/zram0/comp_algorithm) != *"[zstd]"* ]]; then
  # Restarting zram first moves everything in it back into RAM, which thrashes when it's full.
  info "zram holds $((zused >> 20)) MB right now, so it switches to zstd at the next boot"
fi
zramctl | sed 's/^/   /'

step "System: use zram readily"
sudo install -m 644 "$FILES/system/99-surface-zram.conf" /etc/sysctl.d/
sudo sysctl -q --load /etc/sysctl.d/99-surface-zram.conf
ok "swappiness $(cat /proc/sys/vm/swappiness), page-cluster $(cat /proc/sys/vm/page-cluster)"

step "System: cap the system logs at 200 MB"
sudo install -D -m 644 "$FILES/system/journald-size.conf" /etc/systemd/journald.conf.d/size.conf
sudo systemctl restart systemd-journald
sudo journalctl -q --vacuum-size=200M || true
ok "$(journalctl --disk-usage 2>/dev/null)"

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

step "System: Firefox video on the GPU, not the CPU"
# The Go 2's GPU decodes H.264, VP9 and HEVC but not AV1, which YouTube prefers, so Firefox decoded
# AV1 in software: ~30% of a CPU core while a video plays. With AV1 off, sites send VP9 instead.
# Only a default: about:config can still turn it back on. Applies after Firefox restarts.
sudo python3 -I "$FILES/system/firefox-policy.py" "$FILES/system/firefox-policies.json"
ok "Firefox: AV1 off by default ($(grep -c av1 /etc/firefox/policies/policies.json) policy in /etc/firefox/policies)"
