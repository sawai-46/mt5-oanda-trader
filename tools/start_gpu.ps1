Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $repoRoot
try {
  docker compose up -d --build
  Write-Host "[OK] mt5-inference-server started (GPU default)" -ForegroundColor Green
  docker compose ps
} finally {
  Pop-Location
}
