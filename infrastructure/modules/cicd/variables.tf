variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "enable_pipeline" { type = bool }
variable "github_full_repository_id" { type = string }
variable "github_branch" { type = string }
variable "ecr_repository_url" { type = string }
variable "ecr_repository_arn" { type = string }
variable "ecr_repository_name" { type = string }
variable "container_name" { type = string }
variable "cluster_name" { type = string }
variable "service_name" { type = string }
variable "task_execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "app_base_url" {
  type        = string
  description = "http://<alb-dns> used by the verification stage"
}
variable "log_retention_days" { type = number }
variable "artifact_force_destroy" { type = bool }
variable "build_compute_type" { type = string }
variable "deploy_timeout_minutes" { type = number }
