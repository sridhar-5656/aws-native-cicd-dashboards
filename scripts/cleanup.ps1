<#
.SYNOPSIS  Destroys the Terraform-managed infrastructure (after confirmation) and then lists resources that may remain.
.EXAMPLE   .\scripts\cleanup.ps1 -Region us-east-1 -ProjectPrefix devops-dashboard-dev
.NOTES     Does NOT touch the optional Terraform state bucket (infrastructure\bootstrap) - destroy that last, by hand.
#>
param(
    [Parameter(Mandatory)][string]$Region,
    [Parameter(Mandatory)][string]$ProjectPrefix
)
$ErrorActionPreference = "Stop"
Write-Host "WARNING: this permanently deletes the ECS service, load balancer, ECR images (rollback history!), pipeline," -ForegroundColor Yellow
Write-Host "         artifact bucket contents, logs and the VPC created by this project." -ForegroundColor Yellow
if ((Read-Host "Type 'destroy' to continue") -ne "destroy") { Write-Host "Cancelled."; exit 0 }

Push-Location (Join-Path $PSScriptRoot "..\infrastructure\main")
try {
    terraform plan -destroy -var enable_service=true -var initial_image_tag=placeholder -out destroy.tfplan
    if ((Read-Host "Apply the destroy plan above? Type 'yes'") -ne "yes") { Write-Host "Cancelled."; exit 0 }
    terraform apply destroy.tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform destroy failed - fix the error and re-run" }
    Remove-Item destroy.tfplan -ErrorAction SilentlyContinue
} finally { Pop-Location }

Write-Host "`n=== Orphan check (every list below should be empty) ===" -ForegroundColor Cyan
Write-Host "ECR repositories:";      aws ecr describe-repositories --region $Region --query "repositories[?contains(repositoryName, '$ProjectPrefix')].repositoryName" --output text
Write-Host "Load balancers:";        aws elbv2 describe-load-balancers --region $Region --query "LoadBalancers[?contains(LoadBalancerName, '$ProjectPrefix')].LoadBalancerArn" --output text
Write-Host "ECS clusters:";          aws ecs list-clusters --region $Region --query "clusterArns[?contains(@, '$ProjectPrefix')]" --output text
Write-Host "CodePipelines:";         aws codepipeline list-pipelines --region $Region --query "pipelines[?contains(name, '$ProjectPrefix')].name" --output text
Write-Host "CodeBuild projects:";    aws codebuild list-projects --region $Region --query "projects[?contains(@, '$ProjectPrefix')]" --output text
Write-Host "CloudWatch log groups:"; aws logs describe-log-groups --region $Region --query "logGroups[?contains(logGroupName, '$ProjectPrefix')].logGroupName" --output text
Write-Host "CloudWatch alarms:";     aws cloudwatch describe-alarms --region $Region --alarm-name-prefix $ProjectPrefix --query "MetricAlarms[].AlarmName" --output text
Write-Host "NAT gateways (not deleted):"; aws ec2 describe-nat-gateways --region $Region --filter "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text
Write-Host "Unattached Elastic IPs:"; aws ec2 describe-addresses --region $Region --query "Addresses[?AssociationId==null].AllocationId" --output text
Write-Host "VPC endpoints:";         aws ec2 describe-vpc-endpoints --region $Region --query "VpcEndpoints[?State!='deleted'].VpcEndpointId" --output text
Write-Host "S3 buckets:";            aws s3api list-buckets --query "Buckets[?contains(Name, '$ProjectPrefix')].Name" --output text
Write-Host "`nAlso check Billing > Bills and Cost Explorer in 24-48 hours to confirm charges have stopped." -ForegroundColor Yellow
