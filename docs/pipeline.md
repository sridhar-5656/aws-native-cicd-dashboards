# CI/CD pipeline

Pipeline name: `<project>-<env>-pipeline` (created in Phase C). Type V1, artifacts in the encrypted S3 bucket
`<prefix>-artifacts-<account>-<region>` (objects expire after 30 days).

## Stages

| # | Stage | Action | What happens | Blocks next stage if it fails |
|---|-------|--------|--------------|-------------------------------|
| 1 | Source | GitHub via CodeStar connection | Triggers on pushes to `github_branch` (default `main`); outputs source ZIP and variable `SourceVariables.CommitId` | yes |
| 2 | BuildAndTest | CodeBuild `<prefix>-build` | `scripts/local-test.sh --ci` (pytest, `tsc`, vitest) → `docker build` → container smoke test → push to ECR → write `imagedefinitions.json`; exports `IMAGE_TAG` | yes |
| 3 | Deploy | ECS (native action) | Reads `imagedefinitions.json`, registers a task-definition revision with the new image, updates the service, **waits up to `deploy_timeout_minutes`** for a steady state | yes |
| 4 | Verify | CodeBuild `<prefix>-verify` | `scripts/verify-deployment.sh <alb-url> <IMAGE_TAG>`: polls `/health/ready` until 200 **and** `/api/info.image_tag` equals the new tag (up to 10 min) | (last stage) |

### Why a failed test cannot deploy
* All steps run in CodeBuild's `build` phase; the first non-zero exit stops the phase and fails the action.
* `docker push` is the *last* command of that phase; a failed test or image build never reaches it.
* `imagedefinitions.json` is written in `post_build` only when `CODEBUILD_BUILD_SUCCEEDING=1`; without it the Deploy action has nothing to deploy. CodePipeline also does not start the Deploy stage after a failed Build stage.

### `imagedefinitions.json`
```json
[{"name":"app","imageUri":"<account>.dkr.ecr.<region>.amazonaws.com/<repo>:<short-sha>"}]
```
`name` must equal the container name in the task definition (`app`; Terraform passes the same value to CodeBuild as
`CONTAINER_NAME`).

### Image tags
`<short-sha>` (7 chars) is the only tag. ECR tags are immutable, so `a1b2c3d` always refers to the same bytes.
A human-readable release lives in the `VERSION` file and is **inside the image** (`/api/info.version`). You can add
Git tags (`git tag v1.0.0`) for your own history; adding mutable/duplicate ECR tags is intentionally avoided.

### Build reports
`buildspec.yml` publishes the JUnit XML from pytest and vitest as CodeBuild **Reports** (CodeBuild → Report groups).
They are uploaded even when tests fail, so the failing test is visible.

### Privileged mode
Only the **build** project has `privileged_mode = true` (needed to run the Docker daemon). The verify project does not.

## Limits of post-deployment verification
* The ECS deploy action already waits for ECS to report the deployment finished; Verify adds an *external* HTTP check
  and the image-tag match.
* Verify runs **after** the new version is serving traffic. If it fails, the pipeline is red **but ECS has not
  been rolled back** — the circuit breaker only reacts to tasks that fail to start/stay healthy. Roll back with
  [`rollback.md`](rollback.md).
* Verify reaches the ALB from the public internet; with a restricted `allowed_ingress_cidrs` it fails by design.
* The "no healthy targets" alarm and ECS events are the continuous checks; Verify is a one-shot gate.

## Proving that failed CI blocks deployment
1. Note the current version/tag:
   ```powershell
   Invoke-RestMethod "$(terraform -chdir=infrastructure/main output -raw application_url)/api/info" | Select-Object version, image_tag
   ```
2. Add a failing test and push:
   ```powershell
   @'
   def test_deliberate_failure_to_prove_ci_blocks_deploy():
       assert False, "Deliberate failure: the pipeline must stop before Deploy"
   '@ | Set-Content backend\tests\test_deliberate_failure.py
   git add backend\tests\test_deliberate_failure.py
   git commit -m "DEMO: deliberately failing test"
   git push
   ```
3. In CodePipeline: **BuildAndTest** fails; **Deploy** and **Verify** show no new execution. Open **View details →
   CodeBuild → Reports** to see the failed test. Check ECR: no image for the new SHA.
4. Re-run step 1 — version/tag are unchanged.
5. Restore: `git revert HEAD --no-edit; git push` (a new green run deploys the reverted code).

Local equivalent without AWS: add the file, run `.\scripts\local-test.ps1` — it stops with a non-zero exit code.

## Troubleshooting the pipeline
See [troubleshooting.md](troubleshooting.md). Quick map: **Source** red → connection not Available;
**BuildAndTest** red → CodeBuild logs (`/aws/codebuild/<prefix>-build`); **Deploy** red/timeout → ECS service events;
**Verify** red → compare `image_tag` and ALB target health.
