# Validation status — what was actually run

Generated and checked in a Linux sandbox **without Docker, Terraform registry access, PowerShell, or an AWS account**.
No AWS resources were created and no AWS API was called.

## Executed and passed
| Check | Command / method | Result |
|-------|------------------|--------|
| Backend tests | `pytest` (Python 3.12.3) | **21 passed** |
| Frontend type check | `tsc --noEmit` (strict) | no errors |
| Frontend tests | `vitest run` | **10 passed** (2 files) |
| Frontend production build | `vite build` | succeeded; `dist/` produced |
| CI-mode test script | `bash scripts/local-test.sh --ci` | passed; wrote `reports/backend-junit.xml`, `reports/frontend-junit.xml` |
| Production server startup | Gunicorn + `uvicorn_worker.UvicornWorker` in a copy of the container layout (`/srv/backend`, `/srv/VERSION`, `/srv/frontend/dist`) with `APP_REQUIRE_FRONTEND=true` | all six endpoints returned 200; `/api/info` showed injected commit/tag |
| Verification script | `verify-deployment.sh` against that server | passes with the right tag; **fails** (exit 1) with a wrong tag |
| Syntax | `bash -n` on all `.sh`; YAML parse of both buildspecs; `tofu fmt -check -recursive` (OpenTofu 1.8.5) parsed all `.tf` files | OK |
| Terraform wiring | custom script: every module call passes exactly the declared variables and uses only existing outputs | OK |
| PowerShell | brace/parenthesis balance only | OK (not executed) |

## NOT executed — you must verify
| Item | Why | How |
|------|-----|-----|
| `docker build`, container run, smoke test | no Docker daemon in the sandbox | `.\scripts\local-test.ps1 -WithDocker` |
| `terraform init / validate / plan / apply` | provider registry unreachable; no AWS | `deploy.ps1 -Phase A` runs init, fmt, validate, plan first. Resource arguments were written from knowledge of AWS provider ~> 5.70 and **could contain mistakes that only `validate`/`plan` reveal** — fix and commit `.terraform.lock.hcl` once it runs |
| PowerShell scripts | no `pwsh` | run them; read before use |
| CodePipeline / CodeBuild / ECS behaviour | requires AWS | follow README §9–11; the acceptance criteria in the original brief are *not yet demonstrated* |
| `uvicorn-worker`, `public.ecr.aws` base images in Docker | not reachable from the build here (the Python package itself installed and ran) | confirmed at first Docker build |
| Cost figures | from general knowledge | confirm on AWS pricing pages |

## Known design caveats
* Verify stage needs the ALB reachable from the internet and runs after deployment (cannot prevent a bad release).
* Pipeline updates only the container image; resizing the task needs a manual task-definition revision.
* Plain HTTP; single task by default.
