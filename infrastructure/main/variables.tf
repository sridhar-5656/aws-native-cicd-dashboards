variable "aws_region" {
  type        = string
  description = "The single AWS region for everything (for example us-east-1 or ap-south-1)."
}

variable "project_name" {
  type        = string
  description = "Short lowercase name used as a prefix for all resources."
  default     = "cicd-dashboard"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,14}$", var.project_name))
    error_message = "project_name must be 3-15 chars (AWS limits ALB/target group names to 32 characters): lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod). Shown in the dashboard."
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "environment must be 2-8 lowercase alphanumeric characters."
  }
}

# ---- deployment phases -------------------------------------------------------
variable "enable_service" {
  type        = bool
  description = "Phase A = false (foundation only). Phase C = true (ECS service, pipeline, alarms). Needs initial_image_tag."
  default     = false
}

variable "initial_image_tag" {
  type        = string
  description = "Tag of the first image already pushed to ECR (from scripts/bootstrap). Only used when enable_service = true."
  default     = ""
}

# ---- source ------------------------------------------------------------------
variable "github_full_repository_id" {
  type        = string
  description = "GitHub repository as owner/name, e.g. your-user/aws-native-cicd-dashboard."
  validation {
    condition     = can(regex("^[A-Za-z0-9-_.]+/[A-Za-z0-9-_.]+$", var.github_full_repository_id))
    error_message = "Use the form owner/repository."
  }
}

variable "github_branch" {
  type    = string
  default = "main"
}

# ---- network -------------------------------------------------------------------
variable "network_profile" {
  type        = string
  description = "public (cheapest: tasks in public subnets, locked down by security groups) | nat (private subnets + NAT Gateway) | endpoints (private subnets + VPC endpoints)."
  default     = "public"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones (2 or 3)."
  default     = 2
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB on port 80. Restrict to your own IP/32 for a private demo (note: the pipeline's verify stage then cannot reach it)."
  default     = ["0.0.0.0/0"]
}

variable "alb_deletion_protection" {
  type    = bool
  default = false
}

# ---- compute -------------------------------------------------------------------
variable "container_port" {
  type    = number
  default = 8080
}

variable "task_cpu" {
  type        = number
  description = "Fargate CPU units. Supported: 256, 512, 1024, 2048, 4096 ..."
  default     = 256
}

variable "task_memory" {
  type        = number
  description = "Fargate memory in MiB. Must be a valid combination with task_cpu (256 CPU -> 512, 1024 or 2048)."
  default     = 512
}

variable "cpu_architecture" {
  type        = string
  description = "X86_64 (matches the CodeBuild standard image) or ARM64 (would also need an ARM CodeBuild image)."
  default     = "X86_64"
  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "desired_count" {
  type    = number
  default = 1
}

# ---- images, logs, pipeline ----------------------------------------------------
variable "ecr_max_image_count" {
  type        = number
  description = "How many images to keep in ECR (these are your rollback targets)."
  default     = 30
}

variable "ecr_force_delete" {
  type        = bool
  description = "true lets 'terraform destroy' delete the repository even if it still contains images (learning setup)."
  default     = true
}

variable "artifact_force_destroy" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "enable_container_insights" {
  type        = bool
  description = "Adds per-task metrics but also extra CloudWatch charges. Off by default."
  default     = false
}

variable "build_compute_type" {
  type    = string
  default = "BUILD_GENERAL1_SMALL"
}

variable "deploy_timeout_minutes" {
  type    = number
  default = 15
}

# ---- alerting & budget ---------------------------------------------------------
variable "alarm_email" {
  type        = string
  description = "Email for alarm/failure notifications (you must confirm the SNS subscription email). Empty = no subscription."
  default     = ""
}

variable "cpu_alarm_threshold" {
  type    = number
  default = 80
}

variable "memory_alarm_threshold" {
  type    = number
  default = 80
}

variable "monthly_budget_usd" {
  type        = number
  description = "If > 0 and alarm_email is set, creates an account-wide monthly cost budget that emails at 80% actual spend. A budget ALERTS; it does not cap spending."
  default     = 0
}
