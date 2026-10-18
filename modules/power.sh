# power: battery trims measured with upower/turbostat. PCI runtime PM on (Wi-Fi, NVMe and the
# sensor hub sat at power/control=on), PCIe ASPM powersupersave, NMI watchdog off, disk writeback
# every 15 s. USB is untouched, so the LTE modem keeps its no-LPM quirk and power/control=on.

step "Power: PCI runtime PM, ASPM powersupersave, no NMI watchdog"
sudo install -m644 "$FILES/power/99-surface-power.rules" /etc/udev/rules.d/99-surface-power.rules
sudo install -m644 "$FILES/power/99-surface-power.conf" /etc/sysctl.d/99-surface-power.conf
sudo install -m644 "$FILES/power/surface-power-tmpfiles.conf" /etc/tmpfiles.d/surface-power.conf
sudo sysctl -q -p /etc/sysctl.d/99-surface-power.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/surface-power.conf
for d in /sys/bus/pci/devices/*/power/control; do echo auto | sudo tee "$d" >/dev/null; done
ok "applied now and at every boot"

step "Power: power-saver on battery, performance on AC"
# Since the 26.04 upgrade the idle clock doubled (usage-tracker: ~680 -> ~1480 MHz) in the
# balanced profile. Battery -> power-saver (EPP power), charger -> performance; at boot too.
sudo install -m755 "$FILES/power/surface-power-profile" /usr/local/sbin/surface-power-profile
sudo install -m644 "$FILES/power/99-surface-power-profile.rules" /etc/udev/rules.d/99-surface-power-profile.rules
sudo install -m644 "$FILES/power/surface-power-profile.service" /etc/systemd/system/surface-power-profile.service
sudo udevadm control --reload
sudo systemctl daemon-reload
sudo systemctl enable --now surface-power-profile.service
ok "profile now: $(powerprofilesctl get)"
