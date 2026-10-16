# Security

## IAM roles (all created by Terraform; none has AdministratorAccess)
| Role | Trusted service | Allowed actions (summary) | Scope |
|------|-----------------|---------------------------|-------|
| `<prefix>-codepipeline-role` | codepipeline | Read/write artifact bucket; `codebuild:StartBuild/BatchGetBuilds`; `UseConnection`; `ecs:DescribeServices/UpdateService`; register/describe task definitions; `iam:PassRole` | Artifact bucket, the two CodeBuild projects, the one connection, the one service. Task-definition actions require `*` (AWS does not support resource-level scoping). `PassRole` only for the two ECS task roles and only to `ecs-tasks.amazonaws.com` |
| `<prefix>-codebuild-role` | codebuild | Write its own log group; artifact bucket objects; ECR push/describe; create test reports | One ECR repository (`GetAuthorizationToken` requires `*`), its own log group and report groups |
| `<prefix>-verify-role` | codebuild | Write its own log group; read artifacts | Minimal; no ECR/ECS access |
| `<prefix>-task-exec-role` | ecs-tasks | Pull from the one ECR repo; write the one log group | Used by the ECS agent only |
| `<prefix>-task-role` | ecs-tasks | **None** | The app calls no AWS APIs. Add scoped statements only if that changes |

All trust policies carry `aws:SourceAccount` to prevent the cross-account "confused deputy" problem.
No GitHub OIDC role exists because the native CodePipeline→ECS action is used.

## Network
* Internet → **ALB only** (port 80 from `allowed_ingress_cidrs`). To demo privately set it to `["<your-ip>/32"]` (the Verify stage will then fail; remove it from the pipeline or accept that).
* ECS SG ingress: container port **only from the ALB SG**. No SSH, no 22 anywhere, no admin port open to `0.0.0.0/0`.
* ECS SG egress limited to TCP 443 (to the internet in `public`/`nat`; to endpoint SG + S3 prefix list in `endpoints`).
* Default VPC security group is emptied. Task has no execute-command access (`enable_execute_command = false`).
* **HTTP only.** Credentials/session data must never cross this ALB. Production: request an ACM certificate for your domain, add a 443 listener (TLS 1.2+ policy), redirect 80→443, and put Route 53/DNS in front.

## Secrets
* The app needs **no secrets**, so neither Secrets Manager nor Parameter Store is used (adding them would add cost and surface area for nothing).
* If you add one later: store it in Secrets Manager, reference it with `secrets` in the task definition (`valueFrom`), grant `secretsmanager:GetSecretValue` on that one ARN to the **execution role**, never put values in Terraform variables, `.env`, `buildspec.yml`, images or logs.
* Never commit: `.env`, `terraform.tfvars`, `*.tfstate`, AWS keys. `.gitignore` covers these; check `git status` before every commit. If a key ever leaks: deactivate it in IAM immediately, then rotate.
* The API never returns environment variables, credentials, ARNs or account IDs (covered by a unit test). Unhandled errors return a generic message; details go to the log only.

## Data at rest / in transit
S3 (artifacts, optional state): SSE-S3, public access blocked, TLS-only bucket policy. ECR: AES-256, scan on push, immutable tags.
CloudWatch Logs: encrypted by the service by default. Pipeline traffic: HTTPS. Browser→ALB: **HTTP in this learning setup**.
Terraform state **can contain sensitive values** (e.g. resource attributes): keep it out of Git; use the encrypted S3 backend for anything shared or long-lived; restrict who can read the bucket.

## Container
Multi-stage; final image contains only runtime Python deps, app code, and the built frontend. Runs as UID 10001 (non-root).
`.dockerignore` excludes `.git`, `.env*`, venvs, caches, tests, Terraform, docs. Security headers (`nosniff`, `X-Frame-Options: DENY`, CSP `default-src 'self'`) are set by the app.

## Supply chain / scanning (recommended next steps)
* ECR basic scan on push is enabled; view findings: `aws ecr describe-image-scan-findings --repository-name <repo> --image-id imageTag=<tag>`. Consider Amazon Inspector enhanced scanning (extra cost) for continuous scanning.
* Add `pip-audit -r backend/requirements.txt` and `npm audit --omit=dev` to CI (they need network and may fail on new advisories; decide a policy).
* Enable GitHub Dependabot; pin new versions deliberately (requirements and `package-lock.json` are pinned).
* Protect `main` (required reviews/status checks) so only reviewed code reaches the pipeline. Add `terraform validate`/`tflint`/`checkov` for IaC review.
* Enable CloudTrail (management events are on by default for 90 days in the console) and AWS Config if this grows beyond a demo.

## Known limitations of this learning setup
HTTP only; public task IPs in the default `public` profile (protected by SGs); single task; no WAF; ALB access logs disabled; SNS topic not KMS-encrypted (required for CloudWatch alarm delivery with the AWS-managed key).
