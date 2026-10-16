#!/usr/bin/env bash
# Starts the image, waits for readiness, checks key endpoints, then removes the container.
# Usage: bash scripts/smoke-test-container.sh <image> [expected-image-tag]
set -euo pipefail
IMAGE="${1:?image name required}"
EXPECTED_TAG="${2:-}"
NAME="dashboard-smoke-$$"
PORT="${SMOKE_PORT:-18080}"

cleanup() { docker logs "$NAME" 2>&1 | tail -n 20 || true; docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" -p "${PORT}:8080" "$IMAGE" >/dev/null
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health/ready" || true)
  [ "$code" = "200" ] && break
  sleep 2
  if [ "$i" = "30" ]; then echo "Container never became ready (last HTTP $code)"; exit 1; fi
done
for path in / /health /health/live /api/info /api/status; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}${path}")
  [ "$code" = "200" ] || { echo "FAIL: GET $path returned $code"; exit 1; }
  echo "ok  GET $path"
done
if [ -n "$EXPECTED_TAG" ]; then
  actual=$(curl -s "http://127.0.0.1:${PORT}/api/info" | python3 -c 'import sys,json; print(json.load(sys.stdin)["image_tag"])')
  [ "$actual" = "$EXPECTED_TAG" ] || { echo "FAIL: image_tag is '$actual', expected '$EXPECTED_TAG'"; exit 1; }
  echo "ok  image_tag == $EXPECTED_TAG"
fi
echo "Smoke test passed."
