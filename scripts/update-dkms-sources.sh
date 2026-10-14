#!/usr/bin/env bash
# scripts/update-dkms-sources.sh
# Instructions to refresh the DKMS camera sources for a new kernel series.
# This is intentionally not automatic: updating sensor drivers across kernel series
# requires reviewing kernel API changes and re-applying the patches in files/dkms/...

set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cat <<'EOF'
Steps to update the DKMS camera sources for a new kernel series (manual, safe):

1) Fetch the kernel source for the target series (example: 7.1.y):
   git clone --depth 1 --branch v7.1 https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable.git /tmp/linux-7.1

2) Copy the sensor driver files from the kernel tree into this repo's DKMS dir:
   cp /tmp/linux-7.1/drivers/media/i2c/ov8865.c $REPO/files/dkms/surface-go2-cameras-1.0/ov8865.c
   cp /tmp/linux-7.1/drivers/media/i2c/ov5693.c $REPO/files/dkms/surface-go2-cameras-1.0/ov5693.c

3) Re-apply the patches in files/dkms/surface-go2-cameras-1.0/*.patch
   Note: the patches assume the v7.0 sources; you may need to adapt them if the kernel API changed.

4) Build locally to verify:
   sudo apt install -y dkms build-essential linux-headers-$(uname -r)
   sudo rm -rf /usr/src/surface-go2-cameras-1.0
   sudo cp -r $REPO/files/dkms/surface-go2-cameras-1.0 /usr/src/
   sudo dkms install surface-go2-cameras/1.0 -k $(uname -r)

5) If the build fails, inspect /var/lib/dkms/surface-go2-cameras/1.0/build/make.log and adjust the sources/patches.

6) Commit the updated .c files and any adapted patches to the repo, then update README with the supported kernel list.

EOF
