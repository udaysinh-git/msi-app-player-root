#!/bin/bash
# Inject the Magisk /system payload + init hook into an attached Root.vhd.
# Run in WSL2 as root after: wsl --mount <Root.vhd> --vhd --bare
# Needs payload.tar (from setup-magisk.sh) and magisk.rc in this dir.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
PAYLOAD="$HERE/payload.tar"
RC="$HERE/magisk.rc"
[ -f "$PAYLOAD" ] || { echo "payload.tar not found next to this script"; exit 1; }
[ -f "$RC" ] || { echo "magisk.rc not found next to this script"; exit 1; }

MNT=/mnt/bsroot
mkdir -p "$MNT"
PART=""
for p in $(lsblk -lnpo NAME,TYPE | awk '$2=="part"{print $1}'); do
  mountpoint -q "$MNT" && umount "$MNT"
  mount -o ro "$p" "$MNT" 2>/dev/null || continue
  if [ -d "$MNT/android/system/xbin" ]; then PART="$p"; umount "$MNT"; break; fi
  umount "$MNT"
done
[ -n "$PART" ] || { echo "system partition not found"; exit 1; }
echo "system partition: $PART"
mount -o rw "$PART" "$MNT"
SYS="$MNT/android/system"

rm -rf "$SYS/etc/init/magisk"
mkdir -p "$SYS/etc/init/magisk"
tar -xf "$PAYLOAD" -C "$SYS/etc/init/magisk"
cp "$RC" "$SYS/etc/init/magisk.rc"

chown -R 0:0 "$SYS/etc/init/magisk" "$SYS/etc/init/magisk.rc"
chmod 644 "$SYS/etc/init/magisk.rc"
chmod 755 "$SYS/etc/init/magisk" \
          "$SYS/etc/init/magisk/magisk64" "$SYS/etc/init/magisk/magiskboot" \
          "$SYS/etc/init/magisk/magiskinit" "$SYS/etc/init/magisk/magiskpolicy" \
          "$SYS/etc/init/magisk/busybox" "$SYS/etc/init/magisk"/*.sh
sync
ls -l "$SYS/etc/init/magisk.rc"
umount "$MNT"
echo ok
