Updated DKMS behavior: AUTO_DKMS=1 to run apt non-interactively; FORCE_DKMS=1 to attempt DKMS on non-7.0 kernels.

Power-efficiency direction
- I will focus subsequent changes on lowering runtime power where safe: tuning swappiness/zram (already present), setting conservative default governors on battery, ensuring Intel P-state/turbo are configured for Surface, and avoiding heavy background services by default.

Usage examples:
- Interactive DKMS (default): ./install.sh cameras
- Non-interactive DKMS: AUTO_DKMS=1 ./install.sh cameras
- Force DKMS on other kernels: FORCE_DKMS=1 AUTO_DKMS=1 ./install.sh cameras

See scripts/update-dkms-sources.sh for how to refresh driver sources for a new kernel series.
