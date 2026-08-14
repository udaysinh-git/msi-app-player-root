---
name: bluestacks-offline-rooter
description: Root a BlueStacks-family Android emulator on Windows (MSI App Player, BlueStacks 5, and rebrands) by injecting a setuid su into the guest /system offline via WSL2. Use when built-in root and Magisk Direct Install do not work.
---

# BlueStacks offline rooter (agent runbook)

This is a procedure for an agent. Follow the branches in order. Do not skip the
checks; the same emulator brand ships different builds that behave differently.

The method: the guest `/system` is on a `Root.vhd` file. Drop a setuid-root `su`
into `/system` while the emulator is stopped, using WSL2 to mount the ext4. On
boot the binary gives uid 0 to any caller. It persists because it lives in
`/system`, and needs no daemon or boot hook.

This works only when the guest has SELinux `Disabled` or `Permissive`. See the
SELinux branch for the enforcing case.

## 0. Environment facts you need

- Config root: `C:\ProgramData\BlueStacks_<suffix>`. Suffix is `msi5` for MSI App
  Player, `nxt` for stock BlueStacks 5. Search `C:\ProgramData` and
  `C:\Program Files*` for `BlueStacks*`, `MSI`, `App Player`.
- Main config: `<configRoot>\bluestacks.conf` (flat `key="value"` lines).
- Player exe: `C:\Program Files\BlueStacks_<suffix>\HD-Player.exe`.
- Instances: `<configRoot>\Engine\<Name>`. `Pie64`=Android 9, `Rvc64`=Android 11,
  `Tiramisu64`=Android 13. Disks: `Root.vhd` (system), `Data.vhdx` (data).
- Use modern `platform-tools` adb, not the bundled `HD-Adb.exe` (it is v1.0.36 and
  causes `error: closed` on shell while `getprop` still works). If you see that
  symptom, kill all adb servers and use one modern adb.

## 1. Back up before editing

```
Copy-Item <configRoot>\bluestacks.conf <configRoot>\bluestacks.conf.bak-<date>
Copy-Item <configRoot>\Engine\<Name>\*.bstk* <configRoot>\Engine\<Name>\ (as .bak)
```

## 2. Enable ADB (often off by default)

Check `bst.enable_adb_access` in `bluestacks.conf`. If `0`:

1. Stop the instance (`Stop-Process -Name HD-Player -Force`). BlueStacks rewrites
   the conf from memory on exit, so edit only while stopped.
2. Set `bst.enable_adb_access="1"`.
3. Boot.

The instance ADB port is dynamic per boot. Read
`bst.instance.<Name>.status.adb_port`; do not assume `5555` (it is usually
refused). `adb connect 127.0.0.1:<port>`.

## 3. Is it already rooted?

```
adb -s 127.0.0.1:<port> shell su -c id     # uid=0 -> done
adb -s 127.0.0.1:<port> root               # if it elevates -> done
```

On BlueStacks 5.11 both usually fail. Do not trust `enable_root_access` or
`bst.feature.rooting`: `feature.rooting` resets to `0` on every boot in many
builds, so the built-in su never appears, and Magisk then only offers "Select and
Patch a File" (no Direct Install). That is the case this runbook handles.

## 4. SELinux branch (decides the whole approach)

```
adb -s 127.0.0.1:<port> shell getenforce
```

- `Disabled` or `Permissive`: continue. A plain setuid binary works with no
  policy work.
- `Enforcing`: stop. A setuid binary needs the right context
  (`u:object_r:system_file:s0`) and a domain that can `setuid`, plus likely a
  `magiskpolicy` boot step. That is out of scope here; consider the full Magisk
  offline install instead.

## 5. Confirm guest ABI and /system layout

```
adb shell getprop ro.product.cpu.abi        # pick NDK target from this
adb shell mount | grep -E ' /system| /data' # note /system is ro (expected)
```

`/system` is read-only at runtime even for root (the block device is exposed
read-only), so every `/system` write must be done offline. `/data` is writable at
runtime.

## 6. Build su

Target API from Android version: 28 (9), 30 (11), 33 (13). ABI from step 5.

```
x86_64-linux-android28-clang -O2 su.c -o su
```

Dynamic linking is preferred (guest bionic matches the API). Keep a `-static`
build as fallback if the dynamic one fails to load. Pre-flight the binary before
VHD surgery: push to `/data/local/tmp`, `chmod 755`, run `su -c id`. As the shell
user it returns uid 2000 (setuid is a no-op without root), which proves the ELF
loads and the arg parsing works.

`su.c` in this repo elevates to uid/gid 0, clears groups, then execs. It handles
`su`, `su -c "cmd"`, `su <uid> -c "cmd"`, and `su <uid> prog args`.

## 7. Offline injection

Root.vhd is a dynamic VHD, so you cannot `debugfs` at offset 0. Attach it to WSL2
and mount the real ext4 partition.

1. Stop the instance and verify the file is unlocked:
   ```
   [IO.File]::Open("<Root.vhd>",'Open','ReadWrite','None').Close()
   ```
2. Attach: `wsl --mount <Root.vhd> --vhd --bare`.
3. In WSL as root, find the partition and inject. Do it in one WSL invocation from
   a script file (see `reinject.sh`). Two reasons this matters:
   - Device letters shuffle on every attach (`sde` one run, `sdd` the next). Do
     not hardcode. Detect by mounting each partition read-only and checking for
     `android/system/xbin`.
   - The WSL VM idle-restarts between separate `wsl ...` calls, dropping manual
     mounts. Self-mount inside the script.
   - `/system` inside the image is usually under `android/system`, not the
     partition root.

   The injection:
   ```
   mount -o rw <part> /mnt/bsroot
   install -m 6755 -o 0 -g 0 su /mnt/bsroot/android/system/xbin/su
   install -m 6755 -o 0 -g 0 su /mnt/bsroot/android/system/bin/su
   sync; umount /mnt/bsroot
   ```
4. Detach: `wsl --unmount <Root.vhd>`. Confirm the file is unlocked again before
   booting.

`reroot.ps1` wraps steps 1 to 4.

## 8. Verify

```
adb connect 127.0.0.1:<new-port>
adb shell su -c id      # uid=0(root) gid=0(root) groups=0(root)
adb shell su 0 id
```

## PowerShell and WSL quoting

Do not build long `wsl -d <distro> -u root -- bash -lc "..."` strings from
PowerShell. PowerShell expands `$var`, `$(...)`, and `$dev:` inside double quotes
and mangles the bash. Write the bash to a `.sh` file and run
`wsl -u root -- bash /mnt/c/.../script.sh`.

## Cleanup

Remove any test binaries from `/data/local/tmp`. The two `su` copies in `/system`
are the root mechanism; leave them. Because they are in `/system`, root is already
persistent, verified by rebooting the instance.

## When to escalate to full Magisk

Plain root covers full device access. Escalate only if you need managed su
prompts, Zygisk, module support, or DenyList to hide root from apps. That requires
offline injection of the Magisk `/system` payload plus a `bootanim.rc` hijack that
starts `magiskd` and populates `/data/adb/magisk` at boot. `/data` is writable at
runtime, so the boot script can do the `/data/adb` setup. This is more work and
can boot-loop if the hook is wrong; keep the working setuid `su` as the fallback.

## Safety

This `su` grants root to any caller with no prompt. Acceptable for a throwaway dev
VM only. Do not put it on a real device.
