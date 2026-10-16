<#
.SYNOPSIS  Phase B - run tests, build the image and push the FIRST image to ECR (tagged with the short Git SHA).
.EXAMPLE   .\scripts\bootstrap.ps1 -Region us-east-1 -Repository devops-dashboard-dev
.NOTES     Needs: AWS CLI configured, Docker Desktop running, at least one git commit.
           The repository name is the Terraform output "ecr_repository_name".
#>
param(
    [Parameter(Mandatory)][string]$Region,
    [Parameter(Mandatory)][string]$Repository
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Check([string]$what) { if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)" } }

$tag  = (git rev-parse --short=7 HEAD).Trim();  Check "git rev-parse (make a commit first)"
$full = (git rev-parse HEAD).Trim()
$account = (aws sts get-caller-identity --query Account --output text).Trim(); Check "aws sts get-caller-identity"
$registry = "$account.dkr.ecr.$Region.amazonaws.com"
$uri = "$registry/$Repository"

& "$PSScriptRoot\local-test.ps1"
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry; Check "docker login to ECR"

$buildTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
# --platform keeps the image compatible with the Fargate X86_64 task even on ARM laptops.
docker build --platform linux/amd64 `
    --build-arg APP_GIT_COMMIT=$full --build-arg APP_IMAGE_TAG=$tag `
    --build-arg APP_BUILD_TIME=$buildTime `
    -t "${uri}:$tag" .
Check "docker build"

aws ecr describe-images --region $Region --repository-name $Repository --image-ids imageTag=$tag 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Tag $tag already exists in ECR; not pushing again."
} else {
    docker push "${uri}:$tag"; Check "docker push"
}
Write-Host ""
Write-Host "First image pushed: ${uri}:$tag" -ForegroundColor Green
Write-Host "Next (Phase C): .\scripts\deploy.ps1 -Phase C -ImageTag $tag"
