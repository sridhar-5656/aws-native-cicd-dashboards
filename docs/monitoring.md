# Monitoring

## What exists
| Signal | Where | Notes |
|--------|-------|-------|
| App logs (JSON) | CloudWatch Logs `/ecs/<prefix>` (retention `log_retention_days`, default 14) | Fields: `timestamp, level, message, method, path, status, duration_ms, request_id`. Health-check requests are logged at DEBUG, so they do not flood logs |
| Build logs | `/aws/codebuild/<prefix>-build`, `-verify` | |
| Metrics | `AWS/ECS` (CPU, memory per service), `AWS/ApplicationELB` (healthy/unhealthy hosts, 5xx, latency, requests) | Free, standard metrics. Container Insights is **off** (extra cost) — enable with `enable_container_insights = true` |
| Alarms | `<prefix>-ecs-cpu-high`, `-ecs-memory-high`, `-alb-no-healthy-targets`, `-alb-unhealthy-targets`, `-alb-target-5xx` | Thresholds from `cpu_alarm_threshold`, `memory_alarm_threshold` (default 80%, 15 min sustained) |
| Event alerts | EventBridge → SNS | Pipeline execution `FAILED`; ECS `SERVICE_DEPLOYMENT_FAILED` |
| Dashboard | CloudWatch → Dashboards → `<prefix>-overview` | CPU/memory, target health, requests/5xx, latency |

Alarms and events send email only if `alarm_email` is set **and** you confirmed the SNS subscription.
Only standard metrics are used: no custom/high-cardinality metrics.

## Five different meanings of "healthy"
| Layer | Question it answers | Source | Who acts on it |
|-------|--------------------|--------|----------------|
| **Container health** | Is the process alive? | Task-definition `healthCheck` → `GET /health/live` | ECS replaces the container/task when it fails repeatedly |
| **Application readiness** | Can it serve traffic now? | `GET /health/ready` (200/503) | The ALB target-group health check uses this |
| **ALB target health** | Does the load balancer route to this task? | Target group `healthy/unhealthy` | ALB stops sending traffic to unhealthy targets |
| **ECS service deployment health** | Did the rollout reach steady state? | Service `deployments[].rolloutState`, events, circuit breaker | ECS (rollback) and the pipeline's Deploy action (waits) |
| **Pipeline execution status** | Did CI/CD succeed? | CodePipeline execution state | Humans / EventBridge notification |

They can disagree: a task can be *alive* but *not ready* (ALB shows unhealthy); a deployment can be *succeeded*
while a later *Verify* action fails. Always check the layer that matches the symptom.

## Useful commands
```powershell
aws logs tail /ecs/devops-dashboard-dev --region <region> --follow
aws logs filter-log-events --region <region> --log-group-name /ecs/devops-dashboard-dev --filter-pattern '{ $.status >= 500 }'
aws ecs describe-services --region <region> --cluster <cluster> --services <service> --query "services[0].events[:5].[createdAt,message]" --output table
aws elbv2 describe-target-health --region <region> --target-group-arn <tg-arn>
aws cloudwatch describe-alarms --region <region> --alarm-name-prefix devops-dashboard-dev --query "MetricAlarms[].[AlarmName,StateValue]" --output table
```
CloudWatch Logs Insights example (select the `/ecs/<prefix>` group):
```
fields @timestamp, method, path, status, duration_ms
| filter ispresent(status) and status >= 400
| sort @timestamp desc | limit 50
```
Testing an alarm without breaking anything: `aws cloudwatch set-alarm-state --alarm-name <name> --state-value ALARM --state-reason "test"` (the real state returns at the next evaluation).
