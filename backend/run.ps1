# Research Atlas backend launcher for Windows (PowerShell).
#
# Usage (from the backend/ folder):
#   ./run.ps1                 # localhost only (test on the Windows box itself)
#   ./run.ps1 -BindAll        # bind 0.0.0.0 so the Mac can reach it over Tailscale
#
# NEVER port-forward this on your router. Expose it ONLY over Tailscale.
#
# Requires Python 3.12 on PATH as `py -3.12` or `python`.
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
else { throw "Python が見つかりません。https://www.python.org/downloads/ から 3.12 を入れてください。" }

if (-not (Test-Path ".venv")) {
    Write-Host "venv を作成しています..." -ForegroundColor Cyan
    Invoke-Expression "$py -m venv .venv"
    & ".venv\Scripts\python.exe" -m pip install --upgrade pip
    & ".venv\Scripts\python.exe" -m pip install -r requirements.txt
}

$bindHost = if ($BindAll) { "0.0.0.0" } else { "127.0.0.1" }
Write-Host "uvicorn を $bindHost`:$Port で起動します..." -ForegroundColor Green
& ".venv\Scripts\uvicorn.exe" app.main:app --host $bindHost --port $Port
