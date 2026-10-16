# Rollback and failure recovery

## What is automatic vs manual
| Situation | Automatic? | Action |
|-----------|------------|--------|
| New tasks fail to start / fail health checks during a deploy | **Yes** — ECS deployment circuit breaker stops the rollout and rolls back to the previous steady revision; old task kept serving (`minimumHealthyPercent=100`) | Investigate why (troubleshooting §3–6). The pipeline's Deploy stage fails |
| Tests or image build fail | **Yes** — nothing is pushed or deployed | Fix and push |
| New version is **healthy but wrong** (bug, bad UI) | **No** | Manual rollback below |
| Verify stage fails after a successful deploy | **No** — pipeline goes red, ECS is **not** rolled back | Decide; manual rollback if the release is bad |
| Rollback of Git history | **No** | `git revert` (otherwise the next push redeploys the bad code) |

**Never assume a rollback worked until the verification step prints `VERIFIED`.**

## 1. Find the last known-good commit and image
```powershell
# What is running now?
Invoke-RestMethod "$url/api/info" | Select-Object version, git_commit, image_tag
# Pipeline history: console → CodePipeline → <prefix>-pipeline → Execution history (Succeeded rows; commit shown on Source)
aws codepipeline list-pipeline-executions --region <region> --pipeline-name <prefix>-pipeline --query "pipelineExecutionSummaries[].[startTime,status,sourceRevisions[0].revisionId]" --output table
# Images available in ECR (the tag is the first 7 chars of the commit)
aws ecr describe-images --region <region> --repository-name <repo> --query "sort_by(imageDetails,&imagePushedAt)[].[imageTags[0],imagePushedAt,imageScanStatus.status]" --output table
```
Pick the newest tag whose pipeline execution **Succeeded** *before* the bad release. Confirm it still exists in ECR
(the lifecycle policy keeps the newest 30; do not lower `ecr_max_image_count` carelessly, and never delete images by hand that you may need).

## 2. Inspect a failed execution
Console: CodePipeline → execution → failed stage → **View details**. CLI:
```powershell
aws codepipeline get-pipeline-execution --region <region> --pipeline-name <prefix>-pipeline --pipeline-execution-id <id>
aws codepipeline list-action-executions --region <region> --pipeline-name <prefix>-pipeline --filter pipelineExecutionId=<id>
```
For an unhealthy ECS task use [troubleshooting.md](troubleshooting.md) §3–6.

## 3. Redeploy the previous image
```powershell
.\scripts\rollback.ps1 -Region <region> -Cluster <cluster> -Service <service> -Repository <repo> -ImageTag <good-tag> -BaseUrl $url
```
(Linux/macOS: `bash scripts/rollback.sh <region> <cluster> <service> <repo> <good-tag> <url>`.)
The script: checks the image exists → copies the running task definition with the old image → registers it →
updates the service → waits for `services-stable` → runs `verify-deployment` expecting that tag. It throws if
verification fails.

## 4. Verify
`rollback.ps1` already runs it; manually:
```powershell
.\scripts\verify-deployment.ps1 -BaseUrl $url -ExpectedImageTag <good-tag>
aws elbv2 describe-target-health --region <region> --target-group-arn <tg-arn>
```

## 5. Keep Git consistent (important)
The pipeline deploys whatever is on `main`. After an ECS rollback:
```powershell
git revert <bad-commit-sha> --no-edit
git push                     # the pipeline builds + deploys the reverted code as a NEW image (green run)
```
Alternative without waiting for a build: stay on the rolled-back image and fix forward before the next push.

## Alternative: re-run an old pipeline execution
CodePipeline → execution history → **Release change** re-runs the latest source; it cannot redeploy an old commit. Use the script, or revert in Git.
