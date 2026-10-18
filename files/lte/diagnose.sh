#!/bin/bash
# Try each known way to wake the Surface LTE modem's MBIM channel; stop at the first that answers.
# sudo ./files/lte/diagnose.sh
d=$(grep -l 09a5 /sys/bus/usb/devices/*/idProduct | head -1 | xargs dirname)
q() { timeout 20 mbimcli -d /dev/cdc-wdm0 "$@" --query-device-caps 2>&1 | grep -E "Device ID|error" | head -1; }
try() { echo "== $1"; r=$(q $2); echo "   $r"; [[ $r == *"Device ID"* ]] && { echo "WORKS: $1"; exit 0; }; }
systemctl stop ModemManager; trap "systemctl start ModemManager" EXIT
try "plain open (ModemManager stopped)" ""
try "proxy open" "-p"
try "open without MBIM open" "--no-open=1"
echo "== unbind/rebind cdc_mbim"; i=$(basename "$d"):1.0
echo "$i" > /sys/bus/usb/drivers/cdc_mbim/unbind; sleep 2; echo "$i" > /sys/bus/usb/drivers/cdc_mbim/bind; sleep 5
try "after rebind" ""
echo "== USB re-plug"; echo 0 > "$d/authorized"; sleep 3; echo 1 > "$d/authorized"; sleep 10
try "after re-plug" ""
echo "== USB port reset"; usbreset 045e:09a5 >/dev/null 2>&1; sleep 10
try "after port reset" ""
echo "NOTHING WORKED"; journalctl -k -b -o cat | grep -iE "2-3|cdc|wdm" | tail -5
