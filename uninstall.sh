#!/bin/bash
# Remove the injected su from an attached BlueStacks Root.vhd (/system).
# Run in WSL2 as root, after: wsl --mount <Root.vhd> --vhd --bare
set -e

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
rm -f "$SYS/xbin/su" "$SYS/bin/su"
sync
ls -l "$SYS/xbin/su" "$SYS/bin/su" 2>&1 || echo "su removed"
umount "$MNT"
echo ok
