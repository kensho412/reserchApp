# Research Atlas backend launcher for Windows (PowerShell).
#
# Usage (from the backend/ folder):
#   ./run.ps1                 # localhost only (test on the Windows box itself)
#   ./run.ps1 -BindAll        # bind 0.0.0.0 so the Mac can reach it over Tailscale
#
# NEVER port-forward this on your router. Expose it ONLY over Tailscale.
# Requires Python 3.12 on PATH (as `py -3.12` or `python`).
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less files
# as the system codepage (Shift-JIS on JP Windows) and would corrupt non-ASCII text.
param(
    [switch]$BindAll,
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Pick a Python 3.12 interpreter.
$py = $null
if (Get-Command py -ErrorAction SilentlyContinue) { $py = "py -3.12" }
elseif (Get-Command python -ErrorAction SilentlyContinue) { $py = "python" }
else { throw "Python not found. Install 3.12 from https://www.python.org/downloads/" }

if (-not (Test-Path ".venv")) {
    Write-Host "Creating venv..." -ForegroundColor Cyan
    Invoke-Expression "$py -m venv .venv"
    & ".venv\Scripts\python.exe" -m pip install --upgrade pip
    & ".venv\Scripts\python.exe" -m pip install -r requirements.txt
}

$bindHost = if ($BindAll) { "0.0.0.0" } else { "127.0.0.1" }
Write-Host "Starting uvicorn on $bindHost`:$Port ..." -ForegroundColor Green
& ".venv\Scripts\uvicorn.exe" app.main:app --host $bindHost --port $Port
