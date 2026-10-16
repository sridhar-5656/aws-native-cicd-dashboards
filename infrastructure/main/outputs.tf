output "application_url" {
  description = "Open this in a browser (HTTP only in the learning setup)."
  value       = "http://${module.alb.dns_name}"
}
output "alb_dns_name" { value = module.alb.dns_name }
output "ecr_repository_url" { value = module.ecr.repository_url }
output "ecr_repository_name" { value = module.ecr.repository_name }
output "ecs_cluster_name" { value = module.ecs.cluster_name }
output "ecs_service_name" { value = module.ecs.service_name }
output "log_group_name" { value = module.ecs.log_group_name }
output "pipeline_name" { value = module.cicd.pipeline_name }
output "codebuild_project_name" { value = module.cicd.build_project_name }
output "github_connection_arn" { value = module.cicd.connection_arn }
output "github_connection_status" {
  description = "PENDING until you authorize it in the console (Developer Tools > Settings > Connections)."
  value       = module.cicd.connection_status
}
output "artifact_bucket" { value = module.cicd.artifact_bucket }
output "dashboard_name" { value = module.monitoring.dashboard_name }
output "alerts_topic_arn" { value = module.monitoring.sns_topic_arn }
output "aws_account_id_in_use" {
  description = "Informational: the account Terraform is authenticated to (confirm before applying)."
  value       = data.aws_caller_identity.current.account_id
}
