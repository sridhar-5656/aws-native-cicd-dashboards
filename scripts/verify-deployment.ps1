<#
.SYNOPSIS  Polls a deployed environment until /health/ready is 200 (and optionally the expected image tag is live).
.EXAMPLE   .\scripts\verify-deployment.ps1 -BaseUrl http://my-alb-123.us-east-1.elb.amazonaws.com -ExpectedImageTag a1b2c3d
#>
param(
    [Parameter(Mandatory)][string]$BaseUrl,
    [string]$ExpectedImageTag = "",
    [int]$TimeoutSeconds = 600
)
$BaseUrl = $BaseUrl.TrimEnd("/")
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ($true) {
    $ready = 0; $tag = ""
    try {
        $ready = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 "$BaseUrl/health/ready").StatusCode
        if ($ready -eq 200) {
            $info = Invoke-RestMethod -TimeoutSec 10 "$BaseUrl/api/info"
            $tag = $info.image_tag
            if (-not $ExpectedImageTag -or $tag -eq $ExpectedImageTag) {
                Write-Host "VERIFIED: /health/ready=200, image_tag='$tag', version=$($info.version)" -ForegroundColor Green
                Invoke-RestMethod "$BaseUrl/api/status" | ConvertTo-Json
                exit 0
            }
        }
    } catch { }
    Write-Host "waiting... ready=$ready image_tag='$tag' expected='$ExpectedImageTag'"
    if ((Get-Date) -gt $deadline) { Write-Error "VERIFICATION FAILED after ${TimeoutSeconds}s"; exit 1 }
    Start-Sleep -Seconds 10
}
