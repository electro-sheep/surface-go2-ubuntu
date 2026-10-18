#!/bin/bash
# Diagnose MBIM OPEN 'Failure': try OPEN with and without the rx_max/tx_max toggle, MM stopped.
[ $EUID = 0 ] || exec sudo "$0" "$@"
o() { echo "--- $1"; timeout 15 mbimcli -d /dev/cdc-wdm0 --query-device-caps 2>&1 | head -4; }
systemctl stop ModemManager
mv /etc/udev/rules.d/78-surface-lte-fix.rules /run/ 2>/dev/null; udevadm control --reload
d=$(grep -l 09a5 /sys/bus/usb/devices/*/idProduct | head -1); d=${d%/idProduct}
echo 0 >$d/authorized; sleep 2; echo 1 >$d/authorized; sleep 8
o "fresh, no toggle"
n=$(ls -d /sys/class/net/*/cdc_ncm); for v in 16383 16384; do echo $v>$n/rx_max; echo $v>$n/tx_max; done; sleep 1
o "after toggle"
o "again"
mv /run/78-surface-lte-fix.rules /etc/udev/rules.d/; udevadm control --reload
journalctl -k -n 8 --no-pager
systemctl start ModemManager
