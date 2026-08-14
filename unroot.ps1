# Stop instance, remove injected su from Root.vhd via WSL2, boot instance.
# Usage: powershell -ExecutionPolicy Bypass -File unroot.ps1 [-Instance Pie64]
param(
  [string]$Instance  = "Pie64",
  [string]$BstDir    = "C:\ProgramData\BlueStacks_msi5",
  [string]$PlayerExe = "C:\Program Files\BlueStacks_msi5\HD-Player.exe"
)

$ErrorActionPreference = "Stop"
$vhd = Join-Path $BstDir "Engine\$Instance\Root.vhd"
if (-not (Test-Path $vhd)) { throw "Root.vhd not found: $vhd" }

Get-Process HD-Player -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 5

try { $s=[IO.File]::Open($vhd,'Open','ReadWrite','None'); $s.Close() }
catch { throw "Root.vhd is locked" }

wsl --mount $vhd --vhd --bare | Out-Null
try {
  $sh = wsl wslpath -a "$PSScriptRoot\uninstall.sh"
  wsl -u root -- bash $sh
} finally {
  wsl --unmount $vhd | Out-Null
}

Start-Process -FilePath $PlayerExe -ArgumentList '--instance', $Instance
Write-Host "booted without su."
