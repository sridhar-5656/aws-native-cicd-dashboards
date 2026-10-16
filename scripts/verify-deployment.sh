#!/usr/bin/env bash
# Verifies a deployed environment over HTTP.
# Usage: bash scripts/verify-deployment.sh <base-url> [expected-image-tag]
# Polls until /health/ready returns 200 AND (if given) /api/info reports the expected image tag,
# which proves the NEW version is the one answering through the load balancer.
set -euo pipefail
BASE="${1:?base url required, e.g. http://my-alb-123.us-east-1.elb.amazonaws.com}"
BASE="${BASE%/}"
EXPECTED="${2:-}"
TIMEOUT="${VERIFY_TIMEOUT_SECONDS:-600}"
INTERVAL=10
deadline=$(( $(date +%s) + TIMEOUT ))

while true; do
  ready=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$BASE/health/ready" || echo 000)
  tag=""
  if [ "$ready" = "200" ]; then
    tag=$(curl -s -m 10 "$BASE/api/info" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("image_tag") or "")' 2>/dev/null || true)
    if [ -z "$EXPECTED" ] || [ "$tag" = "$EXPECTED" ]; then
      echo "VERIFIED: /health/ready=200, image_tag='${tag}'"
      curl -s -m 10 "$BASE/api/status"; echo
      exit 0
    fi
  fi
  echo "waiting... ready=$ready image_tag='${tag}' expected='${EXPECTED}'"
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "VERIFICATION FAILED after ${TIMEOUT}s (ready=$ready, image_tag='${tag}', expected='${EXPECTED}')" >&2
    exit 1
  fi
  sleep "$INTERVAL"
done
