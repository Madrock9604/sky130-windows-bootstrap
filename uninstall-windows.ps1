# uninstall-windows.ps1 — Clean removal helper for WSL installs
# Usage (Admin PowerShell):
#   .\uninstall-windows.ps1 [-RemoveMagic] [-RemoveUbuntuDistro] [-RemoveVcXsrv]

param(
  [switch]$RemoveMagic,
  [switch]$RemoveUbuntuDistro,
  [switch]$RemoveVcXsrv
)

$ErrorActionPreference = "Stop"

# Resolve repo path to copy linux uninstaller
$repoWin = (Get-Location).Path
$repoWsl = (wsl wslpath -a "$repoWin")

try {
  wsl -d Ubuntu -- bash -lc "cp -f '$repoWsl/linux/uninstall-linux.sh' ~/uninstall-linux.sh && chmod +x ~/uninstall-linux.sh"
  $flag = $RemoveMagic.IsPresent ? " --remove-magic" : ""
  wsl -d Ubuntu -- bash -lc "~/uninstall-linux.sh$flag"
} catch {
  Write-Host "Skipping Linux-side uninstall (Ubuntu not found?)" -ForegroundColor Yellow
}

if ($RemoveVcXsrv) {
  try { winget uninstall -e --id Marha.VcXsrv -h | Out-Null } catch {}
}

if ($RemoveUbuntuDistro) {
  try { wsl --unregister Ubuntu } catch {}
}

Write-Host "Uninstall complete." -ForegroundColor Green
