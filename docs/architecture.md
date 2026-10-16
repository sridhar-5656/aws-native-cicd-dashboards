# Architecture and design decisions

## Components

```
GitHub (main) → CodePipeline ─┬─ Source        CodeStar connection (GitHub app), CODE_ZIP
                              ├─ BuildAndTest  CodeBuild: pytest, vitest, tsc, docker build, smoke test, push to ECR
                              ├─ Deploy        ECS deploy action (imagedefinitions.json) → rolling update + circuit breaker
                              └─ Verify        CodeBuild: poll ALB /health/ready until the new image tag answers
Browser → ALB (public subnets, :80) → ECS Fargate task (:8080, FastAPI serving the React build)
Task → CloudWatch Logs (awslogs). ALB + ECS → CloudWatch metrics → alarms → SNS.
```

One container serves both UI and API: simplest to deploy, no CORS, relative URLs work behind any ALB hostname.

## Key decisions

| # | Decision | Why | Trade-off |
|---|----------|-----|-----------|
| 1 | Single container (Gunicorn + Uvicorn workers, FastAPI serves `frontend/dist`) | Beginner-friendly, one image to promote | UI and API scale together |
| 2 | Version from root `VERSION` file; commit/tag/build-time **baked into the image** via `--build-arg` | One source of truth. Pipeline deploys swap *only the image*, so env vars in the task definition would go stale; values inside the image cannot | Metadata is per image, not per environment |
| 3 | Image tag = short Git SHA, ECR tags **IMMUTABLE** | A tag always means one exact build; rollback is trustworthy | A retried build for the same SHA skips the push (handled in `buildspec.yml`) |
| 4 | Native **ECS deploy action** instead of GitHub→AWS credentials/OIDC | No GitHub-side AWS role needed; AWS-native | Deploy only changes the container image (not CPU/memory/env) |
| 5 | Terraform `ignore_changes = [task_definition]` on the service | CodePipeline registers new revisions; Terraform must not revert the image to the bootstrap tag | Resizing needs the procedure in [Changing task size](#changing-task-size) |
| 6 | Readiness (`/health/ready`) is the **ALB target-group health check**; liveness (`/health/live`) is the **container health check** | A not-ready task receives no traffic but is not killed; a dead process is restarted | Two endpoints to understand (see monitoring.md) |
| 7 | Verify stage = second CodeBuild project calling the public ALB URL | Native, no extra service, proves the *new* tag is live | Needs the ALB to be reachable from the internet; if you restrict `allowed_ingress_cidrs` it will fail; it runs after deployment, so it can detect but not prevent a bad release |
| 8 | Tests/build/smoke/push all in the `build` phase; `post_build` only writes `imagedefinitions.json` if `CODEBUILD_BUILD_SUCCEEDING=1` | `post_build` runs even after `build` fails. Pushing there would publish untested images | — |
| 9 | Base images from `public.ecr.aws/docker/library/*` | Docker Hub anonymous pull limits break shared CI IPs | Mirror may lag Docker Hub slightly |

## Network profiles (`network_profile`)

All profiles: VPC `10.20.0.0/16`, 2 AZs, public subnets (ALB), internet gateway, ALB SG (HTTP from
`allowed_ingress_cidrs`), ECS SG (**only** the container port, **only** from the ALB SG), no SSH, default SG locked down.

| Profile | Where tasks run | How tasks reach ECR/CloudWatch | Recurring cost (approx., us-east-1 — verify) | Notes |
|---------|-----------------|-------------------------------|---------------------------------------------|-------|
| `public` (default) | public subnets, public IP | Internet gateway (egress only 443 allowed by SG) | $0 extra besides ~US$3.65/mo for the task's public IPv4 | Cheapest. Tasks are *not reachable* from the internet because the SG admits only the ALB. A fine learning trade-off; weaker defence-in-depth than private subnets |
| `nat` | private subnets | One NAT Gateway in public subnet 0 + private route `0.0.0.0/0 → NAT` | ≈ US$32/mo hourly + data processing | **Single NAT = single AZ dependency** (if that AZ fails, tasks lose egress). Production uses one NAT per AZ |
| `endpoints` | private subnets | Interface endpoints `ecr.api`, `ecr.dkr`, `logs` (private DNS) + **S3 gateway endpoint** (image layers live in S3) | 3 endpoints × 2 AZ × ~US$0.01/h ≈ US$43/mo + data | No internet path at all; most locked down; usually costlier than NAT at this size |

Private-subnet connectivity requirements (implemented in `modules/network`): route table for private subnets;
`nat` → default route to NAT; `endpoints` → S3 gateway endpoint on the private route table, interface endpoints
in private subnets with an SG allowing 443 **from the ECS SG**, ECS SG egress 443 to the endpoint SG and the S3 prefix
list, and `enable_dns_hostnames` on the VPC so private DNS resolves.

## Availability

2 AZs for the ALB; ECS service `desired_count = 1` by default (one task, one AZ at a time). For real HA use
`desired_count >= 2` (tasks spread across the two subnets) and, for NAT, one NAT per AZ. Rolling deployments use
`minimumHealthyPercent=100, maximumPercent=200` so the old task keeps serving until the new one is healthy
(needs headroom for 2 tasks briefly, which Fargate provides).

## Bootstrap sequence

Circular dependencies exist: the **service** needs an image in ECR; the **ECR repo** must exist first; the
**pipeline's ECS deploy action** needs an existing **service**; the **pipeline** needs an *authorized* GitHub
connection. Resolution — one Terraform root module with an `enable_service` switch:

```
Phase A  terraform apply -var enable_service=false
           VPC, SGs, ECR, ALB + target group + listener, ECS cluster + log group + IAM roles,
           artifact bucket, GitHub connection (PENDING), 2 CodeBuild projects, SNS, dashboard
Manual   Authorize the GitHub connection in the console (status → AVAILABLE)
Phase B  scripts/bootstrap → test + docker build + docker push <ecr>:<short-sha>
Phase C  terraform apply -var enable_service=true -var initial_image_tag=<short-sha>
           task definition (real image) + ECS service + CodePipeline + alarms + failure notifications
Phase D  pipeline's first run starts automatically; later pushes to main deploy automatically
```
The pipeline never runs Terraform. Infrastructure changes are applied by a human with `terraform apply`
(intentional: CI/CD for the *application*, reviewed IaC for the *platform*).

## Changing task size

Because Terraform ignores the service's `task_definition`, changing `task_cpu`/`task_memory` and applying creates a
new revision that the service does not adopt. To resize: (1) keep the variables updated for the record, then
(2) register a new revision from the running one and update the service, e.g. with the same approach as
`scripts/rollback.*` but editing `cpu`/`memory` instead of the image. Valid Fargate pairs: 256 CPU → 512/1024/2048 MiB;
512 → 1024–4096; 1024 → 2048–8192. Check the current table in the AWS docs before choosing larger sizes.

## What this project deliberately does not do

HTTPS/custom domain (documented as the production next step), autoscaling, blue/green (CodeDeploy), WAF,
multi-environment promotion, and any live AWS data inside the app (the app has no AWS API integration, so it
displays **Unavailable** for pipeline status rather than inventing it).
