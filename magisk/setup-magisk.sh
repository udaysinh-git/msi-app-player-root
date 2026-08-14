#!/system/bin/sh
# Run in the guest as root (via the bootstrap su): sh setup-magisk.sh
# Requires the Kitsune Mask app (io.github.huskydg.magisk) installed.
# Populates /data/adb/magisk from the app APK and builds /data/local/tmp/payload.tar
# for offline injection into /system/etc/init/magisk.
set -e

APK=$(pm path io.github.huskydg.magisk | sed 's/package://')
[ -n "$APK" ] || { echo "Kitsune Mask app not installed"; exit 1; }

WORK=/data/local/tmp/mgk
rm -rf "$WORK"; mkdir -p "$WORK"
cd "$WORK"
unzip -o "$APK" 'lib/x86_64/*' 'assets/*' -d "$WORK" >/dev/null 2>&1
SRC="$WORK/lib/x86_64"

D=/data/adb/magisk
mkdir -p "$D" /data/adb/modules /data/adb/post-fs-data.d /data/adb/service.d
cp "$SRC/libmagisk64.so"     "$D/magisk64"
cp "$SRC/libmagiskboot.so"   "$D/magiskboot"
cp "$SRC/libmagiskinit.so"   "$D/magiskinit"
cp "$SRC/libmagiskpolicy.so" "$D/magiskpolicy"
cp "$SRC/libbusybox.so"      "$D/busybox"
cp "$WORK/assets/util_functions.sh" "$WORK/assets/boot_patch.sh" "$WORK/assets/addon.d.sh" "$D/" 2>/dev/null
cp "$WORK/assets/stub.apk" "$D/stub.apk" 2>/dev/null
ln -sf magisk64 "$D/magisk"
cp "$APK" "$D/magisk.apk"
cat > "$D/config" <<EOF
KEEPVERITY=true
KEEPFORCEENCRYPT=true
RECOVERYMODE=false
PREINITDEVICE=
SHA1=
EOF
chmod 755 "$D/magisk64" "$D/magiskboot" "$D/magiskinit" "$D/magiskpolicy" "$D/busybox" "$D"/*.sh

# Payload for /system/etc/init/magisk (offline injection target).
OUT=/data/local/tmp/payload
rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$D"/magisk64 "$D"/magiskboot "$D"/magiskinit "$D"/magiskpolicy "$D"/busybox \
      "$D"/stub.apk "$D"/config "$D"/*.sh "$D"/magisk.apk "$OUT/"
ln -sf magisk64 "$OUT/magisk"
cd /data/local/tmp
tar -cf payload.tar -C "$OUT" .
echo "payload: /data/local/tmp/payload.tar"
ls -l /data/local/tmp/payload.tar
