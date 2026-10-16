<#
.SYNOPSIS  Runs backend + frontend tests (and optionally the Docker build + smoke test) on Windows.
.EXAMPLE   .\scripts\local-test.ps1
.EXAMPLE   .\scripts\local-test.ps1 -WithDocker
#>
param([switch]$WithDocker)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Invoke-Step([string]$Label, [scriptblock]$Block) {
    Write-Host "==> $Label" -ForegroundColor Cyan
    & $Block
    if ($LASTEXITCODE -ne 0) { throw "$Label failed (exit code $LASTEXITCODE)" }
}

if (-not (Test-Path "backend\.venv")) { python -m venv backend\.venv }
Invoke-Step "Install backend dependencies" { & backend\.venv\Scripts\python.exe -m pip install --quiet --disable-pip-version-check -r backend\requirements-dev.txt }
Push-Location backend
try { Invoke-Step "Backend tests (pytest)" { & .venv\Scripts\python.exe -m pytest } } finally { Pop-Location }

Push-Location frontend
try {
    Invoke-Step "Install frontend dependencies" { npm ci --no-audit --no-fund }
    Invoke-Step "Frontend type check" { npm run typecheck }
    Invoke-Step "Frontend tests (vitest)" { npm test }
} finally { Pop-Location }

if ($WithDocker) {
    Invoke-Step "Docker build" { docker build -t devops-dashboard:local . }
    $name = "dashboard-smoke"
    docker rm -f $name 2>$null | Out-Null
    Invoke-Step "Start container" { docker run -d --name $name -p 18080:8080 devops-dashboard:local }
    try {
        $ready = $false
        for ($i = 0; $i -lt 30 -and -not $ready; $i++) {
            Start-Sleep -Seconds 2
            try { $ready = (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:18080/health/ready).StatusCode -eq 200 } catch { }
        }
        if (-not $ready) { docker logs $name; throw "Container never became ready" }
        foreach ($p in "/", "/health", "/health/live", "/api/info", "/api/status") {
            $code = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:18080$p").StatusCode
            Write-Host "GET $p -> $code"
            if ($code -ne 200) { throw "Smoke test failed on $p" }
        }
    } finally { docker rm -f $name | Out-Null }
}
Write-Host "All checks passed." -ForegroundColor Green
