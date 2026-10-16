#!/usr/bin/env bash
# Runs backend (pytest) and frontend (typecheck + vitest) tests.
# Usage: bash scripts/local-test.sh [--ci] [--with-docker]
#   --ci           write JUnit XML to ./reports (used by CodeBuild test reports)
#   --with-docker  also build the image and run the container smoke test
set -euo pipefail
cd "$(dirname "$0")/.."

CI=false; WITH_DOCKER=false
for arg in "$@"; do
  case "$arg" in
    --ci) CI=true ;;
    --with-docker) WITH_DOCKER=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
mkdir -p reports

echo "==> Backend tests"
if [ ! -d backend/.venv ]; then python3 -m venv backend/.venv; fi
# shellcheck disable=SC1091
. backend/.venv/bin/activate
pip install --quiet --disable-pip-version-check -r backend/requirements-dev.txt
BACKEND_ARGS=()
$CI && BACKEND_ARGS+=("--junitxml=../reports/backend-junit.xml")
(cd backend && python -m pytest ${BACKEND_ARGS[@]+"${BACKEND_ARGS[@]}"})
deactivate

echo "==> Frontend tests"
(
  cd frontend
  npm ci --no-audit --no-fund
  npm run typecheck
  if $CI; then
    npx vitest run --reporter=default --reporter=junit --outputFile.junit=../reports/frontend-junit.xml
  else
    npm test
  fi
)

if $WITH_DOCKER; then
  echo "==> Docker build + smoke test"
  docker build -t devops-dashboard:local .
  bash scripts/smoke-test-container.sh devops-dashboard:local
fi
echo "All checks passed."
