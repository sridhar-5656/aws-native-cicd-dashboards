# infrastructure/

| Path         | Purpose                                                                  |
|--------------|--------------------------------------------------------------------------|
| `bootstrap/` | OPTIONAL: S3 bucket for Terraform remote state (local state, one-time).   |
| `main/`      | The root module you run `terraform` in (providers, variables, outputs).   |
| `modules/`   | `network`, `ecr`, `alb`, `ecs`, `cicd`, `monitoring`.                     |

Run commands from `infrastructure/main/`. See `../docs/aws-setup.md` for the exact order.
