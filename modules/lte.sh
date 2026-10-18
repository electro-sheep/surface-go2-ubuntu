# lte: Microsoft-branded Qualcomm X16 modem (045e:09a5, cdc_mbim).

if ! lsusb -d 045e:09a5 >/dev/null 2>&1; then
  step "LTE: no LTE modem found (Wi-Fi-only model?), skipping"
  return 0
fi

step "LTE: modem tools"
apt_install modemmanager libmbim-utils libqmi-utils

step "LTE: wake-up fix (udev rule + resume hook)"
# The modem ignores MBIM until cdc_ncm re-sends SET_NTB_INPUT_SIZE; toggling rx_max/tx_max forces
# that. The udev rule covers boot/replug, the system-sleep hook covers resume from suspend.
sudo install -m 644 "$FILES/lte/78-surface-lte-fix.rules" /etc/udev/rules.d/
sudo install -m 755 "$FILES/lte/surface-lte-fix" /usr/lib/systemd/system-sleep/
sudo udevadm control --reload
# Re-plug the (internal) modem so the rule applies now.
for d in /sys/bus/usb/devices/*; do
  [[ $(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null) == 045e:09a5 ]] || continue
  echo 0 | sudo tee "$d/authorized" >/dev/null; sleep 2; echo 1 | sudo tee "$d/authorized" >/dev/null; sleep 5
done
# apply it now as well, as the rule would on add
sudo /usr/lib/systemd/system-sleep/surface-lte-fix post
sudo systemctl restart ModemManager
ok "installed; waiting for ModemManager to find the modem…"
for _ in $(seq 20); do mmcli -L 2>/dev/null | grep -q /Modem/ && break; sleep 1; done

step "LTE: use the physical SIM slot"
# It ships mapped to the (empty) eSIM. mmcli --set-primary-sim-slot fails with QMI 'Internal'.
wdm=$(ls /dev/cdc-wdm* 2>/dev/null | head -1 || true)
if [[ -n $wdm ]]; then
  if sudo mbimcli -p -d "$wdm" --ms-query-device-slot-mappings 2>/dev/null | grep -q "Executor '0': slot '0'"; then
    ok "already on slot 0 (physical SIM)"
  else
    sudo mbimcli -p -d "$wdm" --ms-set-device-slot-mappings=0 && sudo systemctl restart ModemManager \
      && ok "switched to slot 0 (physical SIM)" || warn "couldn't change the SIM slot"
  fi
  sudo mbimcli -p -d "$wdm" --ms-query-device-slot-mappings 2>/dev/null | sed 's/^/   /' || true
else
  warn "no /dev/cdc-wdm* yet; re-run './install.sh lte' after a reboot"
fi

if [[ -n ${APN:-} ]]; then
  step "LTE: mobile data connection ${APN_NAME:-$APN}"
  name=${APN_NAME:-$APN}
  nmcli -t -f NAME con show | grep -qx "$name" && sudo nmcli con delete "$name" >/dev/null
  sudo nmcli con add type gsm ifname '*' con-name "$name" gsm.apn "$APN" \
    ${APN_USER:+gsm.username "$APN_USER"} ${APN_PASS:+gsm.password "$APN_PASS"} \
    connection.autoconnect yes >/dev/null
  ok "created NetworkManager connection '$name'"
else
  info "set up mobile data in Settings → Mobile Network, or re-run with APN=... (see README)"
fi
