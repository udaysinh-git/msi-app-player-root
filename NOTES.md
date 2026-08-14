# Field notes

Problems hit while building this, and what fixed each. Order is roughly how they
came up. Environment: MSI App Player = BlueStacks 5.11.100.6311, instance Pie64,
Android 9 x86_64, SELinux disabled, Windows 11 with WSL2 and Android NDK.

## ADB looked dead

`adb connect` to 5555 was refused and the instance seemed unreachable.
`bst.enable_adb_access` was `0` in `bluestacks.conf`. Set it to `1` with the app
closed (BlueStacks rewrites the conf from memory on exit, so edit while stopped).

## adb "error: closed" on every shell command

`getprop` worked but `id`, `ls`, `echo` returned `error: closed`. Cause: the
bundled `HD-Adb.exe` is v1.0.36 and there was a newer platform-tools adb on PATH;
two adb servers fighting. Killed all adb, used one modern adb.

## ADB port is dynamic

5555 never connects. The live port is `bst.instance.Pie64.status.adb_port` and it
changes every boot. Read it each time.

## BlueStacks built-in root does not work

`bst.feature.rooting` resets to `0` on every boot (server-gated in this build), so
`enable_root_access` alone gives no `su`. `adb root` is patched out (no-op). Kitsune
Mask only offered "Select and Patch a File", never "Direct Install", because it had
no root to bootstrap from. Conclusion: inject a setuid su into `/system` offline.

## /system is read-only at runtime even as root

The block device is exposed read-only, so `mount -o remount,rw /system` reports ok
but writes still fail. All `/system` changes must be done offline against
`Root.vhd`. `/data` is writable at runtime.

## Root.vhd is a dynamic VHD

Cannot `debugfs` at offset 0. Attached it to WSL2 (`wsl --mount <vhd> --vhd
--bare`) and mounted the real ext4 partition instead.

## /system layout inside the image

The Android `/system` is under `android/system` in the partition, not at the
partition root. Detect the right partition by looking for `android/system/xbin`.

## WSL gotchas

- Device letters shuffle on every `--mount` (`sde` one run, `sdd` the next). Detect
  the partition, do not hardcode.
- The WSL VM idle-restarts between separate `wsl ...` invocations, dropping manual
  mounts. Self-mount inside one script run.

## PowerShell quoting

Long `wsl ... bash -lc "..."` and `adb shell su -c '...'` strings get mangled;
PowerShell expands `$var`, `$(...)`, and `$dev:`. Write bash to a `.sh` file and run
`bash file.sh` / `su -c 'sh file.sh'`.

## su argument parsing

First su handled `su` and `su -c "cmd"` but not `su 0 cmd` (uid, no `-c`), which
scripts use. Rewrote the parser to skip an optional leading uid/name, honor `-c`,
and otherwise exec the remaining args directly.

## Magisk daemon died when started from adb shell

`magisk --daemon` printed "Start daemon on magisk tmpfs" then exited. Its tmpfs
mount lives in the shell's private mount namespace, which is torn down when the
shell exits. The daemon must be launched by init, so a boot hook is required.

## Finding the exact Magisk install recipe

`magisk --daemon` alone is not enough; the missing step was
`magisk64 --setup-sbin`, which is not in `--help`. The authoritative system-mode
recipe (`direct_install_system`) is in the app APK at `res/p9.sh`: files go to
`/system/etc/init/magisk/`, and an init hook runs setup-sbin then the stage
callbacks.

## Native Zygisk does not inject

With Magisk installed and `zygisk=1`, zygote had zero zygisk maps. Native Zygisk
needs boot-time zygote interception that system-mode installs miss. Switched to
ReZygisk (ptrace mode).

## ReZygisk needs built-in Zygisk off

ReZygisk is a standalone Zygisk provider. Its module name showed "Disable Magisk's
built-in Zygisk". Set Magisk `zygisk=0`; then ReZygisk activates.

## ReZygisk missed the boot zygote

ReZygisk's ptrace monitor starts at post-fs-data, after the first zygote has
already forked, so the boot zygote was not injected until a manual
`setprop ctl.restart zygote`. Fixed with `/data/adb/service.d/00zygote-kick.sh`,
which restarts zygote once early in boot. After that, clean boots inject
automatically (ReZygisk status all green, zygote maps non-zero).

## Cosmetic leftovers

- The Magisk app shows "Installed: N/A / Zygisk: No" for a system-mode install.
  The daemon, su, and ReZygisk still work; check via CLI.
- The Magisk `denylist` setting reads 0 while built-in Zygisk is off. That is
  expected with ReZygisk as the provider; DenyList packages are set in the app.
