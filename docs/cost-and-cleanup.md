# Cost review and cleanup

> **This project is not free.** AWS Free Tier rules change by account type, date and region, and **do not cover
> an ALB + Fargate for a full month** in most cases. Check your own account (see the checklist). Prices below are
> **approximate, us-east-1, and from general knowledge — confirm on the AWS pricing pages and the Pricing Calculator.**

## Potentially billable resources
| Resource | Billing model (approx.) | Notes |
|----------|-------------------------|-------|
| Application Load Balancer | ~US$0.0225/h (≈ US$16/mo) + LCU usage | Biggest fixed cost with Fargate; also 2 public IPv4s |
| Fargate task (0.25 vCPU, 0.5 GB, Linux/x86) | ~US$0.0123/h (≈ US$9/mo) per running task | Pay while running; `desired_count = 0` stops this charge |
| Public IPv4 addresses | ~US$0.005/h each (≈ US$3.65/mo): ALB (2) + task (1 in `public` profile) | Charged for all public IPv4s since 2024 |
| NAT Gateway (`nat` profile) | ~US$0.045/h (≈ US$33/mo) + ~US$0.045/GB processed | Not default. Delete when done |
| Interface VPC endpoints (`endpoints` profile) | ~US$0.01/h per endpoint per AZ (3 × 2 ≈ US$43/mo) + data | Not default |
| ECR | ~US$0.10/GB-month stored | Lifecycle keeps the newest 30 images |
| CloudWatch Logs | ~US$0.50/GB ingested + storage | Small app ⇒ cents; retention 14 days |
| CloudWatch alarms / dashboard | Alarms ~US$0.10/mo each (5 alarms); first 3 dashboards free | Container Insights off |
| CodePipeline (V1) | ~US$1/mo per active pipeline (one pipeline free per account) | |
| CodeBuild (BUILD_GENERAL1_SMALL) | ~US$0.005/build-minute (free monthly minutes may apply) | Each push ≈ 4–8 min |
| S3 | pennies | Artifacts expire after 30 days |
| SNS, EventBridge | effectively free at this volume | |
| Data transfer out | per GB beyond free allowances | Negligible for a demo |

Rough default total (`public` profile, 1 task, left running 24/7): **on the order of US$30–40/month**, mostly
ALB + Fargate + public IPv4s. A demo that exists for a few hours costs cents to a couple of dollars.

## Minimal sizing
`task_cpu = 256`, `task_memory = 512`, `desired_count = 1`, build compute `BUILD_GENERAL1_SMALL`, 2 AZs (the ALB
minimum), `network_profile = "public"`. If the app is OOM-killed, step up to `memory = 1024` before raising CPU.
Check the Fargate supported CPU/memory table in the AWS docs before larger sizes.

## Optional local-only mode (zero AWS cost)
Everything except the AWS deployment runs locally: `.\scripts\local-test.ps1 -WithDocker` and the `docker run`
commands in the README. Use this while developing; deploy to AWS only to demonstrate or record a screenshot/video.

## Free Tier / credits checklist
1. Console → **Billing and Cost Management → Free Tier**: see which services are covered, usage, and expiry.
2. Check **Credits** (Billing → Credits) and their expiry and eligible services.
3. Confirm your account's plan (new accounts may have a different free plan/credit model than older ones).
4. Look up each service above on its pricing page for the **current** free-tier terms. Do not assume ALB/Fargate/NAT/endpoints/public IPv4 are free.

## Budget and billing alerts
* Console: **Billing and Cost Management → Budgets → Create budget → Cost budget**, set a small monthly amount
  (e.g. US$10), add alerts at 50%, 80% (actual) and 100% (forecasted) to your email.
* Or set `monthly_budget_usd` and `alarm_email` in tfvars (account-wide budget, 80% actual alert).
* Also enable **Cost Anomaly Detection** (free) and **Billing → Preferences → Receive billing alerts** if offered.
* **A budget or alert does not cap spending.** Charges continue until you delete resources. Billing data lags by hours; check daily while the stack is up.

## Cleanup checklist
1. Stop demonstrating; take screenshots first (pipeline history, ECS, ALB, CloudWatch).
2. Run `.\scripts\cleanup.ps1 -Region <region> -ProjectPrefix devops-dashboard-dev` (or the manual commands below).
3. Confirm every orphan-check list is empty.
4. If you used the remote-state bucket, destroy it **last** (it must be empty; versions included).
5. In GitHub: **Settings → Applications → Installed GitHub Apps → AWS Connector for GitHub → Configure** to revoke access you no longer want.
6. Delete any local AWS credentials you created only for this project (IAM user access keys).
7. Check **Cost Explorer** after 24–48 hours: daily cost should be ~0 for these services.

## `terraform destroy` procedure and warnings
**Destroy deletes your ECR images (your rollback history), logs, the pipeline and artifacts, and the ALB URL stops working. It cannot be undone.**
```powershell
cd infrastructure\main
terraform plan -destroy -var enable_service=true -var initial_image_tag=placeholder -out destroy.tfplan
terraform apply destroy.tfplan
```
(`enable_service=true` ensures service/pipeline/alarms are included in the plan; `ecr_force_delete` and
`artifact_force_destroy` default to `true` so non-empty repository/bucket do not block destruction.)
If destroy fails (e.g. ENI still attached), wait a few minutes and re-run the same commands.

## Orphan check (after destroy)
```powershell
$r="<region>"; $p="devops-dashboard-dev"
aws ecr describe-repositories --region $r --query "repositories[?contains(repositoryName,'$p')].repositoryName"
aws elbv2 describe-load-balancers --region $r --query "LoadBalancers[?contains(LoadBalancerName,'$p')].LoadBalancerArn"
aws ecs list-clusters --region $r
aws codepipeline list-pipelines --region $r
aws codebuild list-projects --region $r
aws logs describe-log-groups --region $r --query "logGroups[?contains(logGroupName,'$p')].logGroupName"
aws cloudwatch describe-alarms --region $r --alarm-name-prefix $p
aws ec2 describe-nat-gateways --region $r --filter "Name=state,Values=available,pending"
aws ec2 describe-addresses --region $r --query "Addresses[?AssociationId==null]"
aws ec2 describe-vpc-endpoints --region $r
aws ec2 describe-vpcs --region $r --filters "Name=tag:Project,Values=devops-dashboard"
aws s3api list-buckets --query "Buckets[?contains(Name,'$p')].Name"
aws codestar-connections list-connections --region $r
aws budgets describe-budgets --account-id (aws sts get-caller-identity --query Account --output text)
```
`scripts/cleanup.ps1` runs most of these. Everything should be empty (the account-wide budget is only removed if Terraform created it).
