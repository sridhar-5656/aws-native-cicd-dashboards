data "aws_caller_identity" "current" {}

locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  cluster_name   = "${local.name_prefix}-cluster"
  service_name   = "${local.name_prefix}-svc"
  container_name = "app"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "network" {
  source                = "../modules/network"
  name_prefix           = local.name_prefix
  aws_region            = var.aws_region
  vpc_cidr              = var.vpc_cidr
  az_count              = var.az_count
  network_profile       = var.network_profile
  container_port        = var.container_port
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
}

module "ecr" {
  source          = "../modules/ecr"
  name            = local.name_prefix
  max_image_count = var.ecr_max_image_count
  force_delete    = var.ecr_force_delete
}

module "alb" {
  source              = "../modules/alb"
  name_prefix         = local.name_prefix
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  security_group_id   = module.network.alb_security_group_id
  container_port      = var.container_port
  health_check_path   = "/health/ready"
  deletion_protection = var.alb_deletion_protection
}

module "ecs" {
  source                    = "../modules/ecs"
  name_prefix               = local.name_prefix
  cluster_name              = local.cluster_name
  service_name              = local.service_name
  container_name            = local.container_name
  container_port            = var.container_port
  aws_region                = var.aws_region
  app_environment           = var.environment
  ecr_repository_url        = module.ecr.repository_url
  ecr_repository_arn        = module.ecr.repository_arn
  initial_image_tag         = var.initial_image_tag
  enable_service            = var.enable_service
  cpu                       = var.task_cpu
  memory                    = var.task_memory
  cpu_architecture          = var.cpu_architecture
  desired_count             = var.desired_count
  log_retention_days        = var.log_retention_days
  enable_container_insights = var.enable_container_insights
  task_subnet_ids           = module.network.task_subnet_ids
  assign_public_ip          = module.network.assign_public_ip
  ecs_security_group_id     = module.network.ecs_security_group_id
  target_group_arn          = module.alb.target_group_arn
  listener_arn              = module.alb.listener_arn
}

module "cicd" {
  source                    = "../modules/cicd"
  name_prefix               = local.name_prefix
  aws_region                = var.aws_region
  enable_pipeline           = var.enable_service # the ECS deploy action needs an existing service
  github_full_repository_id = var.github_full_repository_id
  github_branch             = var.github_branch
  ecr_repository_url        = module.ecr.repository_url
  ecr_repository_arn        = module.ecr.repository_arn
  ecr_repository_name       = module.ecr.repository_name
  container_name            = local.container_name
  cluster_name              = local.cluster_name
  service_name              = local.service_name
  task_execution_role_arn   = module.ecs.execution_role_arn
  task_role_arn             = module.ecs.task_role_arn
  app_base_url              = "http://${module.alb.dns_name}"
  log_retention_days        = var.log_retention_days
  artifact_force_destroy    = var.artifact_force_destroy
  build_compute_type        = var.build_compute_type
  deploy_timeout_minutes    = var.deploy_timeout_minutes
}

module "monitoring" {
  source                  = "../modules/monitoring"
  name_prefix             = local.name_prefix
  aws_region              = var.aws_region
  cluster_name            = local.cluster_name
  service_name            = local.service_name
  enable_service          = var.enable_service
  enable_pipeline         = var.enable_service
  pipeline_name           = "${local.name_prefix}-pipeline"
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  alarm_email             = var.alarm_email
  cpu_alarm_threshold     = var.cpu_alarm_threshold
  memory_alarm_threshold  = var.memory_alarm_threshold
}

# Optional account-wide cost alert. Alerts only; AWS Budgets does not stop spending.
resource "aws_budgets_budget" "monthly" {
  count        = var.monthly_budget_usd > 0 && var.alarm_email != "" ? 1 : 0
  name         = "${local.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }
}
