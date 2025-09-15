# sky130-windows.ps1 — Windows 10/11 (x64) WSL bootstrap for Magic + SKY130
# Usage (Admin PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\sky130-windows.ps1

$ErrorActionPreference = "Stop"
function Step($pct, $msg) { Write-Progress -Activity "SKY130/WSL setup" -PercentComplete $pct -Status $msg }

if (-not [Environment]::Is64BitOperatingSystem) {
  Write-Host "This requires 64-bit Windows. For 32-bit/Win8, use a VM and run linux/sky130-linux.sh inside it." -ForegroundColor Yellow
  exit 1
}

$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = [int]$cv.CurrentBuild

Step 5 "Enabling WSL + VM Platform…"
Start-Process dism.exe -ArgumentList "/online","/enable-feature","/featurename:VirtualMachinePlatform","/all","/norestart" -Wait -NoNewWindow
Start-Process dism.exe -ArgumentList "/online","/enable-feature","/featurename:Microsoft-Windows-Subsystem-Linux","/all","/norestart" -Wait -NoNewWindow

Step 10 "Ensuring latest WSL…"
try { wsl --set-default-version 2 | Out-Null } catch {}
try { wsl --update | Out-Null } catch {}

$distro = "Ubuntu"
$have = (wsl -l -q) -contains $distro
if (-not $have) {
  Step 15 "Installing Ubuntu… (first run will ask you to create a UNIX user)"
  try { wsl --install -d $distro } catch {
    Write-Host "If Ubuntu opened, finish user creation, close it, then re-run this script." -ForegroundColor Yellow
    exit 0
  }
  Write-Host "Complete the Ubuntu first-run setup, then re-run this script." -ForegroundColor Yellow
  exit 0
}

# On Windows 10, offer VcXsrv fallback (WSLg is native on Win11)
if ($build -lt 22000) {
  Step 20 "Installing optional VcXsrv X-server (fallback for Win10)…"
  try { winget install -e --id Marha.VcXsrv -h | Out-Null } catch {}
}

# Resolve repo path for copying linux scripts into Ubuntu
$repoWin = (Get-Location).Path
$repoWsl = (wsl wslpath -a "$repoWin")

Step 40 "Copying bootstrap script into Ubuntu…"
wsl -d Ubuntu -- bash -lc "cp -f '$repoWsl/linux/sky130-linux.sh' ~/sky130-linux.sh && chmod +x ~/sky130-linux.sh"

Step 60 "Running Ubuntu bootstrap (this may take a while)…"
wsl -d Ubuntu -- bash -lc "~/sky130-linux.sh"

Step 100 "Done."
Write-Host "`nOpen Ubuntu and run:  magic-sky130   (or magic-sky130-xsafe / magic-sky130-nogl)" -ForegroundColor Green
