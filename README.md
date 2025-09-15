# SKY130 on Windows — classroom bootstrap (WSL/Ubuntu)

Installs **WSL + Ubuntu**, then builds **Magic** + **SKY130 PDK** inside Ubuntu. Works on Windows 11 and Windows 10 (with optional VcXsrv fallback).

## Quick start (Admin PowerShell)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\sky130-windows.ps1
