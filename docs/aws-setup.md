# AWS setup, step by step

Everything below uses **Windows PowerShell**. Replace `<region>` with your chosen region.

## 0. Account hygiene (do once)
1. Enable MFA on the root user; do not use root for this project.
2. Create an IAM Identity Center user (or an IAM user) for yourself and configure the CLI:
   ```powershell
   aws configure sso      # or: aws configure
   aws sts get-caller-identity
   ```
   The `Account` shown must be the account you intend to deploy to.
3. Create a **billing alert** before creating resources: see [cost-and-cleanup.md](cost-and-cleanup.md#budget-and-billing-alerts).

## 1. Choose the region
Set `aws_region` in `infrastructure/main/terraform.tfvars`. All resources, the console and CLI commands must use
that region (the console region selector top-right!). The GitHub connection and pipeline are regional.

## 2. (Optional) remote state
Local state is the default (`infrastructure/main/terraform.tfstate`, git-ignored). It can contain sensitive
infrastructure details; do not share or commit it, and back it up if the project matters. For long-lived or shared use:
```powershell
cd infrastructure\bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars    # set aws_region
terraform init; terraform apply                         # creates the state bucket (review the plan first)
terraform output -raw backend_config_snippet            # paste into infrastructure\main\backend.tf
cd ..\main; terraform init -migrate-state               # answer yes to copy local state to S3
```
S3 native locking (`use_lockfile`) needs Terraform ≥ 1.10. Delete the old local state file afterwards.

## 3. Configure variables
```powershell
cd infrastructure\main
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```
Required: `aws_region`, `github_full_repository_id`. Commit `.terraform.lock.hcl` after the first `terraform init`.

## 4. Phase A — foundation
```powershell
.\scripts\deploy.ps1 -Phase A
```
Equivalent manual commands (from `infrastructure\main`):
```powershell
terraform init
terraform fmt -check -recursive ..
terraform validate
terraform plan -var enable_service=false -out tfplan
terraform apply tfplan
```
Expected success line: `Apply complete! Resources: N added, 0 changed, 0 destroyed.` followed by outputs.

## 5. Authorize the GitHub connection (manual, required)
1. Console → **Developer Tools** → **Settings** → **Connections**.
2. Select `<project>-<env>-github` (status **Pending**) → **Update pending connection**.
3. **Install a new app** → GitHub login pop-up → choose your account/organization → install **AWS Connector for GitHub**,
   granting access to *only* the project repository → back in AWS click **Connect**.
4. Expected: status **Available**.
   `aws codestar-connections list-connections --region <region> --query "Connections[].[Name,ConnectionStatus]" --output table`

## 6. Phase B — first image
```powershell
$repo = terraform -chdir=infrastructure/main output -raw ecr_repository_name
.\scripts\bootstrap.ps1 -Region <region> -Repository $repo
```
Expected last lines: `First image pushed: <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<sha>` and the Phase C hint.
Confirm: `aws ecr describe-images --region <region> --repository-name $repo --query "imageDetails[].imageTags"`

## 7. Phase C — ECS service and pipeline
```powershell
.\scripts\deploy.ps1 -Phase C -ImageTag <sha>
```
Then watch: Console → **CodePipeline** → `<prefix>-pipeline`; ECS → Clusters → `<prefix>-cluster` → Services.

## 8. Discover the URL and verify
```powershell
terraform -chdir=infrastructure/main output application_url
.\scripts\verify-deployment.ps1 -BaseUrl <that-url> -ExpectedImageTag <sha>
```

## 9. Email alerts (optional)
Set `alarm_email` and re-run Phase C's apply (use the same `-ImageTag` as currently deployed *or any existing tag*:
it is ignored by the service). Click the confirmation link in the SNS email — unconfirmed subscriptions receive nothing.
