<#
.SYNOPSIS  Guided Terraform runs for Phase A (foundation) and Phase C (service + pipeline).
           Shows the plan and ASKS FOR CONFIRMATION before any apply. Nothing is created without a "yes".
.EXAMPLE   .\scripts\deploy.ps1 -Phase A
.EXAMPLE   .\scripts\deploy.ps1 -Phase C -ImageTag a1b2c3d
#>
param(
    [Parameter(Mandatory)][ValidateSet("A", "C")][string]$Phase,
    [string]$ImageTag
)
$ErrorActionPreference = "Stop"
$dir = Join-Path $PSScriptRoot "..\infrastructure\main"
Set-Location $dir

if (-not (Test-Path "terraform.tfvars")) { throw "Copy terraform.tfvars.example to terraform.tfvars and edit it first." }
if ($Phase -eq "C" -and -not $ImageTag) { throw "Phase C needs -ImageTag (the tag pushed by scripts\bootstrap.ps1)." }

terraform init
terraform fmt -check -recursive ..
terraform validate

if ($Phase -eq "A") { $vars = @("-var", "enable_service=false") }
else { $vars = @("-var", "enable_service=true", "-var", "initial_image_tag=$ImageTag") }

terraform plan @vars -out tfplan
Write-Host ""
Write-Host "Review the plan above. Applying will create billable AWS resources (ALB, Fargate, etc.)." -ForegroundColor Yellow
$answer = Read-Host "Type 'yes' to apply, anything else to cancel"
if ($answer -ne "yes") { Write-Host "Cancelled. Nothing was changed."; exit 0 }
terraform apply tfplan
if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
Remove-Item tfplan -ErrorAction SilentlyContinue
terraform output

if ($Phase -eq "A") {
    Write-Host ""
    Write-Host "MANUAL STEP: authorize the GitHub connection in the AWS console before Phase C (see docs/aws-setup.md)." -ForegroundColor Yellow
}
