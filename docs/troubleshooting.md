# Troubleshooting

Start from the **symptom**, check the **right layer** (see [monitoring.md](monitoring.md#five-different-meanings-of-healthy)).

## 1. Pipeline: Source stage fails
* Error mentions connection / `Unable to use Connection` → connection still **Pending**. Authorize it
  ([aws-setup.md §5](aws-setup.md#5-authorize-the-github-connection-manual-required)).
* Wrong repo/branch → check `github_full_repository_id` (`owner/name`) and `github_branch` in tfvars; re-apply.
* Pushes do not trigger → confirm the push went to the configured branch; check the connection's GitHub app still has access to the repository.

## 2. Pipeline: BuildAndTest fails
Open the action → **View details** → CodeBuild logs (or `aws logs tail /aws/codebuild/<prefix>-build`).
| Message / symptom | Likely cause | Fix |
|-------------------|--------------|-----|
| A pytest/vitest failure | Real test failure | Fix the code/test; CodeBuild **Reports** show which test |
| `Cannot connect to the Docker daemon` | Privileged mode off | Terraform sets `privileged_mode = true` on the build project; re-apply if changed |
| `npm ci` lockfile error | `package.json` and `package-lock.json` out of sync | Run `npm install` locally and commit the lockfile |
| `no basic auth credentials` / `denied` on push | ECR login failed or role lacks permission | Check `ECR_REPOSITORY_URI` env var; role `<prefix>-codebuild-role` policy |
| `toomanyrequests` pulling a base image | Registry rate limit | Base images already use ECR Public; do not change them to Docker Hub |
| `Could not determine commit SHA` | `COMMIT_ID` variable missing | The pipeline action passes `#{SourceVariables.CommitId}`; do not remove it |
| Smoke test timeout | App crashes at start | Run `docker run` locally; read the printed container logs |
| `Tag ... already exists in ECR: skipping push` (info) | Re-run for the same commit | Expected with immutable tags |

## 3. Pipeline: Deploy fails or times out
```powershell
aws ecs describe-services --region <region> --cluster <cluster> --services <service> --query "services[0].events[:10].[createdAt,message]" --output table
aws ecs describe-services --region <region> --cluster <cluster> --services <service> --query "services[0].deployments[].[status,rolloutState,rolloutStateReason]" --output table
```
* `rolloutState = FAILED` → the circuit breaker stopped the rollout and **rolled back** to the previous revision; find out why new tasks failed (sections 4–6).
* `AccessDenied ... iam:PassRole` → pipeline role must pass exactly the execution and task roles (set by Terraform); did the roles get recreated? Re-apply.
* `Container name ... not found in task definition` → `imagedefinitions.json` name differs from the container name (`app`).

## 4. Task cannot pull the image (`CannotPullContainerError`)
```powershell
aws ecs list-tasks --region <region> --cluster <cluster> --service-name <service> --desired-status STOPPED
aws ecs describe-tasks --region <region> --cluster <cluster> --tasks <task-arn> --query "tasks[0].[stoppedReason,containers[0].reason]"
```
| Cause | Check |
|-------|-------|
| Tag does not exist | `aws ecr describe-images --repository-name <repo> --image-ids imageTag=<tag>` (lifecycle policy may have expired old images) |
| Wrong architecture (`exec format error`, or manifest has no matching platform) | Build with `--platform linux/amd64` (bootstrap does) and keep `cpu_architecture = X86_64` |
| No route to ECR (private subnet) | `nat`: NAT + private default route exist? `endpoints`: ecr.api, ecr.dkr, logs endpoints + S3 gateway endpoint + SG rules exist? |
| Public profile but no public IP | Task subnets must be public and `assign_public_ip = true` (module output) |
| SG egress | ECS SG must allow outbound 443 |
| Execution role | Needs `ecr:GetAuthorizationToken` + pull actions on this repo, logs write |

## 5. Targets are unhealthy
```powershell
aws elbv2 describe-target-health --region <region> --target-group-arn <tg-arn>
```
Read `Reason`/`Description`:
* `Target.FailedHealthChecks` → hit `/health/ready` in the task logs; a `503` means the app says it is not ready (see response `checks`). With `APP_REQUIRE_FRONTEND=true` the React build must exist in the image.
* `Target.Timeout` → SG: ECS SG must allow the container port **from the ALB SG**; ALB SG egress must allow the same.
* Port mismatch → container port, task port mapping, target group port, SG rules must all be `8080`.
* Empty target list → service not created yet (Phase A only) or the tasks are not running.
* ALB DNS shows 503 → no healthy target; 504 → target timeouts.

## 6. Tasks keep stopping
```powershell
aws ecs describe-tasks --region <region> --cluster <cluster> --tasks <task-arn> --query "tasks[0].[stopCode,stoppedReason,containers[0].exitCode]"
aws logs tail /ecs/<prefix> --region <region> --since 30m
```
* `Essential container in task exited`, exit code **137** → out-of-memory kill: raise `task_memory` (see architecture.md → resizing) .
* `Task failed container health checks` → `/health/live` not answering on 8080 within 30 s start period; check logs.
* `ResourceInitializationError` → network/endpoint/IAM problem pulling secrets/images/logs (see §4).

## 7. Verify stage fails
Logs: `/aws/codebuild/<prefix>-verify`. `waiting... ready=200 image_tag='<old>'` → the old task is still answering (deployment not finished or rolled back). `ready=000` → ALB not reachable from the internet (restricted `allowed_ingress_cidrs`?) or DNS not ready. Then use [rollback.md](rollback.md) if the new release is bad.

## 8. Terraform problems
| Problem | Fix |
|---------|-----|
| `enable_service = true requires initial_image_tag` | Run Phase B first and pass `-ImageTag` |
| `ResourceInitializationError`/`image not found` after Phase C apply | The tag was never pushed; confirm in ECR |
| Name already exists | A previous partial deployment left resources; run the orphan check in [cost-and-cleanup.md](cost-and-cleanup.md) |
| `Error acquiring the state lock` | Another run is active, or a crashed run left a lock; confirm nobody is running Terraform, then `terraform force-unlock <id>` |
| Budget resource `AccessDenied` | Your IAM user needs `budgets:*`; or leave `monthly_budget_usd = 0` and create the budget in the console |
