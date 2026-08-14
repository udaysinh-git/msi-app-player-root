# msi-app-player-root

Root the MSI App Player (BlueStacks 5, Android 9 "Pie64") by writing a setuid `su`
into the guest `/system` offline. No Magisk daemon and no boot hook. It persists
across reboots because it lives in `/system`.

Works on plain BlueStacks 5 too (MSI App Player is a rebranded BlueStacks 5).

Tested on MSI App Player = BlueStacks `5.11.100.6311`, instance `Pie64`, Android 9
(API 28), x86_64, SELinux disabled. Other 5.x builds and instances (`Rvc64`,
`Tiramisu64`) should work when SELinux is `Disabled` or `Permissive`; adjust the
NDK API level for the Android version.

## Why not the usual methods

On BlueStacks 5.11 the built-in root path is dead:

- `bst.feature.rooting` resets to `0` on every boot, so `enable_root_access` alone
  gives no `su`.
- `adb root` is a no-op (patched out).
- Kitsune Mask / Magisk Delta only offers "Select and Patch a File", never
  "Direct Install", because there is no root to bootstrap from.

The guest runs with SELinux disabled and mounts `/system` with `suid`, so a
setuid-root binary in `/system` is enough. `/system` is read-only at runtime, so
the write is done offline against the `Root.vhd` file.

## Requirements

- Windows 10/11 with WSL2 (a distro that can mount ext4, e.g. Ubuntu).
- Android NDK to build `su`, or use `prebuilt/su` (x86_64, API 28).
- BlueStacks 5 / MSI App Player. Default instance is `Pie64`.

## Build su

```
x86_64-linux-android28-clang -O2 su.c -o su
```

`su.c` elevates to uid/gid 0 and execs the request. It handles `su`,
`su -c "cmd"`, `su <uid> -c "cmd"`, and `su <uid> prog args`.

To verify the shipped binary against source, check it with `SHA256SUMS`:
`sha256sum -c SHA256SUMS`, or in PowerShell
`Get-FileHash prebuilt/su -Algorithm SHA256`.

## Install

1. Enable ADB once: set `bst.enable_adb_access="1"` in
   `C:\ProgramData\BlueStacks_msi5\bluestacks.conf`, with the app closed.
2. Run the injector:

```
powershell -ExecutionPolicy Bypass -File reroot.ps1
```

`reroot.ps1` stops the instance, attaches `Root.vhd` to WSL2
(`wsl --mount --vhd --bare`), runs `reinject.sh`, detaches, and boots. Pass
`-Instance Rvc64` (Android 11) or `-Instance Tiramisu64` (Android 13) for other
images.

`reinject.sh` mounts the ext4 partition that contains `android/system`, copies
`su` to `/system/xbin/su` and `/system/bin/su` as `root:root` mode `6755`, then
unmounts.

## Use

The instance ADB port is dynamic per boot. Read it from the config:

```
Select-String status.adb_port "C:\ProgramData\BlueStacks_msi5\bluestacks.conf"
adb connect 127.0.0.1:<port>
adb shell su -c id
```

Expected: `uid=0(root) gid=0(root) groups=0(root)`. Port `5555` does not work; use
`status.adb_port`.

## Remove root

```
powershell -ExecutionPolicy Bypass -File unroot.ps1
```

Deletes both `su` copies from `/system` via the same offline mount, then boots.

## What root unlocks

Once `su` works you have uid 0 in the guest. Practical uses:

- adb automation as root: `adb shell su -c '...'` for scripts, input events,
  screencap, packet capture.
- Read and edit app private data under `/data/data` to debug or reverse engineer
  your own apps.
- App security testing: run frida-server, hook with Frida or objection, dump
  memory, bypass SSL pinning.
- HTTPS interception: drop a Burp or mitmproxy CA into the system trust store
  (`/system/etc/security/cacerts`) so apps trust it. System store writes use the
  same offline WSL step as the su inject, since runtime `/system` is read-only.
- Debloat, add system apps, swap fonts, edit `build.prop` and system props
  (offline).
- System-wide adblock or firewall through the hosts file and `iptables`.
- Packet capture with `tcpdump`, which already ships in the image.
- Check how your own app behaves on a rooted device.

Needs full Magisk, not plain su:

- Zygisk modules and LSPosed.
- DenyList to hide root from apps that block rooted devices.
- Managed per-app su prompts.

## Files

- `su.c` setuid su source.
- `prebuilt/su` compiled x86_64 binary (NDK, API 28).
- `reinject.sh` WSL2 mount and copy.
- `reroot.ps1` full stop/inject/boot cycle.
- `uninstall.sh` / `unroot.ps1` remove the injected su.
- `SHA256SUMS` checksum for `prebuilt/su`.
- `AgentSkill.md` step-by-step runbook, including the enforcing-SELinux and other
  emulator instances (Rvc64, Tiramisu64) branches.

## Notes

- This is a blanket `su` with no prompt. That is fine for a throwaway dev VM. Do
  not ship it to a real device.
- After a factory reset the `Root.vhd` is recreated, so rerun `reroot.ps1`.
- `/data` stays writable at runtime, so you can still set up a full Magisk on top
  if you want managed grants, Zygisk, or DenyList. That needs a boot hook and is
  out of scope here.

## License

MIT. See LICENSE.
