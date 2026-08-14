# Offline-install Magisk (system mode) into the BlueStacks Pie64 instance.
# Prereq: root already present (see repo root reroot.ps1) and the Kitsune Mask
# app installed in the guest. Run guest-side setup-magisk.sh first to build the
# payload, then this pulls it and injects offline.
#
# Usage: powershell -ExecutionPolicy Bypass -File install-magisk.ps1 [-Port 5555]
param(
  [string]$Instance  = "Pie64",
  [string]$BstDir    = "C:\ProgramData\BlueStacks_msi5",
  [string]$PlayerExe = "C:\Program Files\BlueStacks_msi5\HD-Player.exe",
  [int]$Port         = 0
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$vhd  = Join-Path $BstDir "Engine\$Instance\Root.vhd"
$adb  = (Get-Command adb).Source

if ($Port -eq 0) {
  $line = Select-String -Path (Join-Path $BstDir "bluestacks.conf") -Pattern 'status\.adb_port="(\d+)"'
  $Port = [int]$line.Matches[0].Groups[1].Value
}
$dev = "127.0.0.1:$Port"
& $adb connect $dev | Out-Null

# 1. Build payload in the guest, pull it next to this script.
& $adb -s $dev push "$here\setup-magisk.sh" /data/local/tmp/setup-magisk.sh | Out-Null
& $adb -s $dev shell "/system/xbin/su -c 'sh /data/local/tmp/setup-magisk.sh'"
& $adb -s $dev pull /data/local/tmp/payload.tar "$here\payload.tar" | Out-Null

# 2. Install the ReZygisk service.d kick (persists on /data).
& $adb -s $dev push "$here\00zygote-kick.sh" /data/adb/service.d/00zygote-kick.sh | Out-Null
& $adb -s $dev shell "/system/xbin/su -c 'chmod 755 /data/adb/service.d/00zygote-kick.sh'"

# 3. Offline inject payload + magisk.rc into /system.
Get-Process HD-Player -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 5
wsl --mount $vhd --vhd --bare | Out-Null
try {
  $sh = wsl wslpath -a "$here\inject-magisk.sh"
  wsl -u root -- bash $sh
} finally {
  wsl --unmount $vhd | Out-Null
}

Start-Process -FilePath $PlayerExe -ArgumentList '--instance', $Instance
Write-Host "Booted. Magisk daemon + su come up via /system/etc/init/magisk.rc."
Write-Host "For Zygisk/DenyList: install ReZygisk as a module, then in the Magisk"
Write-Host "app set built-in Zygisk OFF (ReZygisk replaces it) and reboot. See MAGISK.md."
