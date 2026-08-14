#!/bin/bash
# Inject the setuid su into an attached BlueStacks Root.vhd (/system).
# Run in WSL2 as root, after: wsl --mount <Root.vhd> --vhd --bare
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
SU="$HERE/su"
[ -f "$SU" ] || SU="$HERE/prebuilt/su"
[ -f "$SU" ] || { echo "su binary not found; build it (see README) or use prebuilt/su"; exit 1; }

MNT=/mnt/bsroot
mkdir -p "$MNT"

# Find the attached ext4 partition that holds android/system.
PART=""
for p in $(lsblk -lnpo NAME,TYPE | awk '$2=="part"{print $1}'); do
  mountpoint -q "$MNT" && umount "$MNT"
  mount -o ro "$p" "$MNT" 2>/dev/null || continue
  if [ -d "$MNT/android/system/xbin" ]; then PART="$p"; umount "$MNT"; break; fi
  umount "$MNT"
done
[ -n "$PART" ] || { echo "system partition not found; is Root.vhd attached with --bare?"; exit 1; }

echo "system partition: $PART"
mount -o rw "$PART" "$MNT"
SYS="$MNT/android/system"
install -m 6755 -o 0 -g 0 "$SU" "$SYS/xbin/su"
install -m 6755 -o 0 -g 0 "$SU" "$SYS/bin/su"
sync
stat -c '%n uid=%u gid=%g mode=%a' "$SYS/xbin/su" "$SYS/bin/su"
umount "$MNT"
echo ok
