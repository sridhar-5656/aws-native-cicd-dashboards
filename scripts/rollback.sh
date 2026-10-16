#!/usr/bin/env bash
# Manual rollback: point the ECS service at a previously pushed image tag, wait, and verify.
# Usage: bash scripts/rollback.sh <region> <cluster> <service> <ecr-repo-name> <image-tag> <base-url>
# Needs: aws CLI, python3. This does NOT change Git; see docs/rollback.md for keeping Git and ECS in sync.
set -euo pipefail
REGION="$1"; CLUSTER="$2"; SERVICE="$3"; REPO="$4"; TAG="$5"; BASE_URL="$6"

aws ecr describe-images --region "$REGION" --repository-name "$REPO" --image-ids imageTag="$TAG" >/dev/null \
  || { echo "Image tag $TAG not found in ECR repo $REPO. Aborting."; exit 1; }
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
IMAGE="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${TAG}"

CURRENT_TD="$(aws ecs describe-services --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text)"
echo "Current task definition: $CURRENT_TD"

aws ecs describe-task-definition --region "$REGION" --task-definition "$CURRENT_TD" --query taskDefinition --output json \
| IMAGE="$IMAGE" python3 -c '
import json, os, sys
td = json.load(sys.stdin)
for c in td["containerDefinitions"]:
    c["image"] = os.environ["IMAGE"]
keep = ["family","taskRoleArn","executionRoleArn","networkMode","containerDefinitions","volumes",
        "placementConstraints","requiresCompatibilities","cpu","memory","runtimePlatform"]
json.dump({k: td[k] for k in keep if k in td}, sys.stdout)
' > /tmp/rollback-taskdef.json

NEW_TD="$(aws ecs register-task-definition --region "$REGION" --cli-input-json file:///tmp/rollback-taskdef.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
echo "Registered: $NEW_TD"
aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$NEW_TD" >/dev/null
echo "Waiting for service to become stable (this can take several minutes)..."
aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"
bash "$(dirname "$0")/verify-deployment.sh" "$BASE_URL" "$TAG"
echo "Rollback to $TAG verified."
