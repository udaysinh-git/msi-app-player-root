# Full Magisk (system mode) on BlueStacks Pie64

This turns the bootstrap `su` setup into a real Magisk: persistent `magiskd`,
managed su, modules, and Zygisk + DenyList via ReZygisk. Verified on Kitsune Mask
(Magisk Delta) `v27.2-kitsune-4`, BlueStacks 5.11 / MSI App Player, Android 9 x86_64.

## Prereqs

- Root already working (repo root `reroot.ps1`, the setuid su).
- Kitsune Mask app installed in the guest (`io.github.huskydg.magisk`). It ships
  the Magisk binaries; these scripts pull them from its APK.

## How it works

BlueStacks has no boot image to patch, so Magisk runs in system mode:

- Binaries live in `/system/etc/init/magisk/` (written offline into `Root.vhd`).
- `magisk.rc` in `/system/etc/init/` wires the boot stages. Android init parses
  `/system/etc/init/*.rc`. The key line runs at post-fs-data:
  `magisk64 --auto-selinux --setup-sbin /system/etc/init/magisk /sbin`, which
  builds the `/sbin` MAGISKTMP, then `--post-fs-data`, `--service`,
  `--boot-complete`, `--zygote-restart` fire from init triggers.
- `--auto-selinux` handles the SELinux-disabled guest.
- The daemon state and modules live in `/data/adb` (writable at runtime), so the
  init hook needs no runtime `/system` writes.

Native Magisk Zygisk does not inject zygote here (system-mode, no ramdisk). Use
ReZygisk (ptrace mode) instead.

## Install

1. Boot with root present. Confirm `adb shell su -c id` is uid 0.
2. Run from Windows:

```
powershell -ExecutionPolicy Bypass -File install-magisk.ps1
```

   It runs `setup-magisk.sh` in the guest (populates `/data/adb/magisk`, builds
   `payload.tar`), drops the `service.d` kick, then stops the instance and injects
   `payload.tar` + `magisk.rc` into `/system` offline via WSL2, and boots.

3. Verify:

```
adb shell su -c id                 # uid=0
adb shell su -c '/sbin/magisk -v'  # daemon version
```

## Zygisk + DenyList (ReZygisk)

1. Install ReZygisk as a module (github.com/PerformanC/ReZygisk):

```
adb push ReZygisk-*-release.zip /data/local/tmp/rezygisk.zip
adb shell su -c '/sbin/magisk --install-module /data/local/tmp/rezygisk.zip'
```

2. Disable Magisk built-in Zygisk so ReZygisk provides it:

```
adb shell su -c '/sbin/magisk --sqlite "REPLACE INTO settings (key,value) VALUES(\"zygisk\",0)"'
```

3. The `00zygote-kick.sh` in `/data/adb/service.d` restarts zygote once early in
   boot. ReZygisk's ptrace monitor comes up at post-fs-data, after the first
   zygote fork, so without the kick the boot zygote is not injected.
4. Reboot. Check ReZygisk went green:

```
adb shell su -c 'grep ^description /data/adb/modules/rezygisk/module.prop'
# [Monitor: ..., ReZygisk 64-bit: ..., ReZygisk 32-bit: ...]
adb shell su -c 'for z in $(pgrep -f zygote64); do grep -c zygisk /proc/$z/maps; done'
# non-zero -> zygote injected
```

DenyList packages are added in the Magisk app (Superuser / DenyList) and enforced
by ReZygisk. The `denylist` setting reads 0 with built-in Zygisk off; that is
expected when ReZygisk is the Zygisk provider.

## Notes

- The Magisk app may show "Installed: N/A / Zygisk: No". That is cosmetic for a
  system-mode install; the daemon, su, and ReZygisk still work (check via CLI).
- The bootstrap setuid `su` at `/system/xbin/su` stays as a fallback. It is a
  blanket, detectable root, so it undercuts DenyList hiding. For strict hiding,
  remove it (repo root `unroot.ps1` deletes it) once Magisk su is confirmed.
- Undo: `magisk --remove-modules`, delete `/system/etc/init/magisk*` offline,
  remove `/data/adb`.
