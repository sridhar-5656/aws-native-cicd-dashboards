<#
.SYNOPSIS  Manual rollback: point the ECS service at a previously pushed image tag, wait, then verify over HTTP.
.EXAMPLE   .\scripts\rollback.ps1 -Region us-east-1 -Cluster devops-dashboard-dev-cluster -Service devops-dashboard-dev-svc `
               -Repository devops-dashboard-dev -ImageTag a1b2c3d -BaseUrl http://my-alb.us-east-1.elb.amazonaws.com
#>
param(
    [Parameter(Mandatory)][string]$Region, [Parameter(Mandatory)][string]$Cluster,
    [Parameter(Mandatory)][string]$Service, [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$ImageTag, [Parameter(Mandatory)][string]$BaseUrl
)
$ErrorActionPreference = "Stop"
function Check([string]$what) { if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)" } }

aws ecr describe-images --region $Region --repository-name $Repository --image-ids imageTag=$ImageTag | Out-Null
Check "Image tag $ImageTag was not found in ECR - aborting"
$account = (aws sts get-caller-identity --query Account --output text).Trim()
$image = "$account.dkr.ecr.$Region.amazonaws.com/${Repository}:$ImageTag"

$currentTd = (aws ecs describe-services --region $Region --cluster $Cluster --services $Service --query "services[0].taskDefinition" --output text).Trim()
Check "describe-services"
Write-Host "Current task definition: $currentTd"

$td = aws ecs describe-task-definition --region $Region --task-definition $currentTd --query taskDefinition --output json | ConvertFrom-Json
Check "describe-task-definition"
foreach ($c in $td.containerDefinitions) { $c.image = $image }
$keep = "family","taskRoleArn","executionRoleArn","networkMode","containerDefinitions","volumes","placementConstraints","requiresCompatibilities","cpu","memory","runtimePlatform"
$new = [ordered]@{}
foreach ($k in $keep) { if ($td.PSObject.Properties.Name -contains $k) { $new[$k] = $td.$k } }
$file = Join-Path $env:TEMP "rollback-taskdef.json"
# UTF-8 without BOM, as the AWS CLI expects
[System.IO.File]::WriteAllText($file, ($new | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding $false))

$newTd = (aws ecs register-task-definition --region $Region --cli-input-json "file://$file" --query "taskDefinition.taskDefinitionArn" --output text).Trim()
Check "register-task-definition"
Write-Host "Registered: $newTd"
aws ecs update-service --region $Region --cluster $Cluster --service $Service --task-definition $newTd | Out-Null
Check "update-service"
Write-Host "Waiting for the service to become stable (can take several minutes)..."
aws ecs wait services-stable --region $Region --cluster $Cluster --services $Service
Check "wait services-stable"
& "$PSScriptRoot\verify-deployment.ps1" -BaseUrl $BaseUrl -ExpectedImageTag $ImageTag
if ($LASTEXITCODE -ne 0) { throw "Rollback was applied but verification FAILED - investigate before assuming recovery" }
Write-Host "Rollback to $ImageTag verified." -ForegroundColor Green
