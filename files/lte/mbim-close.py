#!/usr/bin/env python3
# Send a bare MBIM CLOSE to the modem. If its firmware still holds a session from before the
# upgrade/reboot, it rejects every OPEN with "Failure" until the old session is closed.
# sudo python3 -I files/lte/mbim-close.py [/dev/cdc-wdm0]
import os, select, struct, sys

dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/cdc-wdm0"
fd = os.open(dev, os.O_RDWR)
os.write(fd, struct.pack("<III", 0x00000002, 12, 1))  # MBIM_CLOSE_MSG: type, length, transaction id
if select.select([fd], [], [], 5)[0]:
    t, length, tid, status = struct.unpack("<IIII", os.read(fd, 4096)[:16])
    print(f"close-done: type 0x{t:08x} status {status} ({'ok' if status == 0 else 'error'})")
else:
    print("no reply to CLOSE within 5 s")
os.close(fd)
