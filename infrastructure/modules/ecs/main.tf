data "aws_caller_identity" "current" {}

locals {
  log_group_name = "/ecs/${var.name_prefix}"
  # Same probe as the Dockerfile HEALTHCHECK: liveness only (independent of optional dependencies).
  health_command = "python -c \"import urllib.request as u; u.urlopen('http://127.0.0.1:${var.container_port}/health/live', timeout=3)\""
}

# ------------------------------------------------------------------ cluster + logs
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

# ------------------------------------------------------------------ IAM: task EXECUTION role
# Used by the ECS agent (not by your code) to pull the image and write logs.
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "task_execution" {
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level scoping
  }
  statement {
    sid       = "PullFromThisRepositoryOnly"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid       = "WriteToThisLogGroupOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "least-privilege-execution"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

# ------------------------------------------------------------------ IAM: task role (application identity)
# Deliberately has NO permissions: the app calls no AWS APIs. Add scoped statements here if that changes.
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ------------------------------------------------------------------ task definition + service (Phase C)
resource "aws_ecs_task_definition" "app" {
  count                    = var.enable_service ? 1 : 0
  family                   = "${var.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = var.container_name
    image     = "${var.ecr_repository_url}:${var.initial_image_tag}"
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    # Version/commit/image-tag metadata is baked into the image at build time, so a pipeline
    # deployment (which only swaps the image) can never leave stale values here.
    environment = [
      { name = "APP_ENVIRONMENT", value = var.app_environment },
      { name = "APP_LOG_LEVEL", value = "INFO" },
      { name = "PORT", value = tostring(var.container_port) },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "app"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", local.health_command]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    stopTimeout = 30
  }])

  lifecycle {
    precondition {
      condition     = var.initial_image_tag != ""
      error_message = "enable_service = true requires initial_image_tag (push the first image with scripts/bootstrap first)."
    }
  }
}

resource "aws_ecs_service" "app" {
  count           = var.enable_service ? 1 : 0
  name            = var.service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app[0].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  deployment_minimum_healthy_percent = 100 # keep the old task serving until the new one is healthy
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  # If new tasks cannot become healthy, ECS stops the rollout and rolls back to the last
  # steady-state deployment automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.task_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # CodePipeline registers new task-definition revisions; Terraform must not revert them.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_iam_role_policy.task_execution, terraform_data.listener_dependency]
}

# listener_arn is accepted so the service always waits for the listener (target group must be attached to an LB).
resource "terraform_data" "listener_dependency" {
  input = var.listener_arn
}
