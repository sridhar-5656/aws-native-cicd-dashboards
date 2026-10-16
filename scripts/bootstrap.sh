#!/usr/bin/env bash
# Phase B: build the app, run tests, and push the FIRST image to ECR (tagged with the short Git SHA).
# Usage: bash scripts/bootstrap.sh <aws-region> <ecr-repository-name>
# Requires: AWS CLI configured (aws sts get-caller-identity works), Docker running, git commit made.
set -euo pipefail
cd "$(dirname "$0")/.."
REGION="${1:?aws region required}"
REPO="${2:?ecr repository name required (terraform output ecr_repository_name)}"

TAG="$(git rev-parse --short=7 HEAD)"
FULL="$(git rev-parse HEAD)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
URI="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}"

bash scripts/local-test.sh
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
# --platform matches the Fargate task's X86_64 architecture even when building on Apple Silicon.
docker build --platform linux/amd64 \
  --build-arg APP_GIT_COMMIT="$FULL" --build-arg APP_IMAGE_TAG="$TAG" \
  --build-arg APP_BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t "${URI}:${TAG}" .
if aws ecr describe-images --region "$REGION" --repository-name "$REPO" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists in ECR; not pushing again."
else
  docker push "${URI}:${TAG}"
fi
echo
echo "First image pushed: ${URI}:${TAG}"
echo "Next: terraform apply with -var enable_service=true -var initial_image_tag=${TAG}"
