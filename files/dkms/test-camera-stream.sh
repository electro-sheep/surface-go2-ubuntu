#!/usr/bin/env bash
# files/dkms/test-camera-stream.sh
# Simple helper that runs 'cam' to capture a number of frames from a camera index
# Usage: test-camera-stream.sh -c <camera-index> -f <frames> -s <WIDTHxHEIGHT>

set -euo pipefail
usage(){
  echo "Usage: $0 -c CAMERA_INDEX -f FRAMES -s WIDTHxHEIGHT"
  exit 2
}
CAM=-1
FRAMES=10
SIZE=1280x720
while getopts ":c:f:s:" o; do
  case "${o}" in
    c) CAM=${OPTARG} ;; 
    f) FRAMES=${OPTARG} ;; 
    s) SIZE=${OPTARG} ;; 
    *) usage ;;
  esac
done
shift $((OPTIND-1))
if [[ $CAM -lt 0 ]]; then usage; fi
if ! command -v cam >/dev/null 2>&1; then echo "cam tool not found"; exit 3; fi
W=${SIZE%x*}
H=${SIZE#*x}
TMP=$(mktemp --tmpdir test-camera.XXXXXX)
chmod 600 "$TMP"
if timeout 30 cam -c "$CAM" -C "$FRAMES" -s width=$W,height=$H >"$TMP" 2>&1; then
  CNT=$(grep -c 'seq:' "$TMP" || true)
  if [[ $CNT -ge $FRAMES ]]; then
    echo "OK: captured $CNT frames"
    rm -f "$TMP"
    exit 0
  else
    echo "FAIL: only $CNT frames captured (expected $FRAMES)"
    sed -n '1,200p' "$TMP"
    exit 1
  fi
else
  echo "FAIL: cam command failed"
  sed -n '1,200p' "$TMP"
  rm -f "$TMP"
  exit 1
fi
