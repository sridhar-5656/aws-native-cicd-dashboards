# Interview questions and answers

**1. Walk me through what happens when you push to `main`.**
GitHub notifies CodePipeline through the CodeStar connection. Source outputs the code and the commit ID. CodeBuild runs pytest, the TypeScript check and vitest, builds the multi-stage image tagged with the short SHA, smoke-tests the container, pushes to ECR, and writes `imagedefinitions.json`. The ECS deploy action registers a new task-definition revision and updates the service; ECS rolls tasks one at a time behind the ALB. A final CodeBuild stage polls the ALB until the new image tag answers `/health/ready`.

**2. How do you guarantee untested code is never deployed?**
Tests, image build and push are sequential commands in CodeBuild's `build` phase, so the first failure stops it before `docker push`. `post_build` (which still runs after a failure) only writes `imagedefinitions.json` when `CODEBUILD_BUILD_SUCCEEDING=1`. A failed Build stage means the Deploy stage never starts.

**3. Why Fargate rather than EC2?**
No hosts to patch or scale, per-second billing of exactly the task size, simple for a small service. Trade-offs: higher unit price than well-packed EC2, fewer tuning options.

**4. Why does the task pull the image from ECR in a private subnet need extra networking?**
Image layers come from ECR (API + Docker registry endpoints) and S3, and logs go to CloudWatch. Private subnets have no internet route, so you need a NAT Gateway or VPC endpoints (`ecr.api`, `ecr.dkr`, `logs` interface endpoints and an S3 gateway endpoint) plus matching route tables and security-group rules.

**5. Why is the default network profile `public`? Is that unsafe?**
It avoids NAT/endpoint cost (~US$30–45/month). Tasks get public IPs but their security group only admits the container port from the ALB's security group, so they are not reachable from the internet. It is weaker defence-in-depth than private subnets; production should use private subnets.

**6. Explain liveness vs readiness and who uses each.**
Liveness (`/health/live`) means the process is running and is used by the ECS container health check — failure restarts the container. Readiness (`/health/ready`) means it can serve traffic and is used by the ALB target group — failure removes it from rotation without killing it. Liveness deliberately has no external dependencies, to avoid restart storms when a dependency is down.

**7. What does the ECS deployment circuit breaker do, and what does it not do?**
It stops a rolling deployment whose tasks repeatedly fail to start or become healthy and rolls back to the last steady revision. It does not detect a *working but wrong* release; that needs alarms, verification, and manual rollback.

**8. Why does the service have `ignore_changes = [task_definition]`?**
CodePipeline creates new task-definition revisions on each deploy. Without ignoring it, the next `terraform apply` would revert the service to the bootstrap image.

**9. How did you solve the bootstrap chicken-and-egg problem?**
Phase A builds the foundation (ECR, ALB, IAM, connection); a script builds and pushes the first image; Phase C creates the task definition, service and pipeline with `enable_service=true`. The pipeline needs an existing service, and the service needs an existing image.

**10. Why immutable ECR tags with the commit SHA?**
A tag always identifies one build, so rollback and audit are trustworthy and `latest` ambiguity is avoided. The cost: retried builds for the same SHA must skip the push (handled).

**11. How is least privilege applied?**
Five separate roles (pipeline, build, verify, task execution, task). Each is scoped to specific ARNs where AWS supports it (one repository, one service, one bucket, one connection); `ecr:GetAuthorizationToken` and task-definition actions require `*`. `iam:PassRole` is limited to the two task roles and to `ecs-tasks.amazonaws.com`. The application task role has no permissions at all.

**12. Why no GitHub OIDC role?**
The native CodePipeline→ECS action means GitHub never needs AWS credentials. OIDC is needed only for GitHub Actions deploying directly.

**13. How would you add HTTPS?**
Request an ACM certificate for your domain (DNS validation in Route 53), add an HTTPS listener on 443 with a modern TLS policy forwarding to the target group, make the port-80 listener redirect to 443, open 443 in the ALB SG, and point a Route 53 alias at the ALB.

**14. How do you monitor and what would page you?**
JSON logs to CloudWatch, standard ECS and ALB metrics, alarms for no healthy targets, unhealthy targets, 5xx, sustained CPU/memory, and EventBridge notifications for pipeline and ECS deployment failures to SNS. "No healthy targets" would page first, since it means the site is down.

**15. How do you roll back?**
Automatic for deployments that never become healthy (circuit breaker). Otherwise run the rollback script with a known-good tag from ECR, verify via `/api/info` and target health, then `git revert` so Git and production agree.

**16. What are the limits of your verification stage?**
It runs after the new version is live, so it detects rather than prevents; it needs internet reachability to the ALB; it does not trigger an automatic rollback. Blue/green with CodeDeploy and test traffic would gate traffic shifting.

**17. How would you scale this?**
Raise `desired_count` to ≥ 2 across both AZs, add ECS service auto scaling on CPU/ALB request count, one NAT per AZ if private, WAF, HTTPS, separate staging/production with promotion, and split frontend/backend if they need independent scaling.

**18. What would you improve next?**
Blue/green deployments, a staging environment, Inspector scanning, `pip-audit`/`npm audit` and IaC scanning in CI, OIDC-based Terraform automation with plan review in pull requests, and a custom domain.

**19. Where are the cost risks?**
ALB and public IPv4 addresses run hourly regardless of traffic, NAT Gateway and interface endpoints are costly, and a forgotten stack keeps billing. Budgets alert but do not cap; `cleanup.ps1` plus an orphan check mitigates this.

**20. How do you keep the app version in one place?**
The root `VERSION` file; `config.py` reads it (repo or `/srv/VERSION` in the image), the buildspec logs it, and the UI shows what `/api/info` returns. Commit/tag/build time are build args baked into the image.
