data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  service_arn_prefix = "arn:aws:ecs:${var.aws_region}:${local.account_id}:service/${var.cluster_name}/"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ecs_dimensions     = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  alb_dimensions     = { TargetGroup = var.target_group_arn_suffix, LoadBalancer = var.alb_arn_suffix }
}

# ------------------------------------------------------------------ notifications (SNS is effectively free at this volume)
# Not encrypted with the AWS-managed SNS key on purpose: CloudWatch alarms cannot publish to topics
# encrypted with the AWS-managed key. Alert text contains no secrets.
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid       = "AllowOwnerAccount"
    actions   = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:ListSubscriptionsByTopic"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
  statement {
    sid       = "AllowAlarmsAndEvents"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# The recipient must click the confirmation link AWS emails them.
resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ------------------------------------------------------------------ alarms (only once the service exists)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.enable_service ? 1 : 0
  alarm_name          = "${var.name_prefix}-ecs-cpu-high"
  alarm_description   = "Average ECS service CPU above ${var.cpu_alarm_threshold}% for 15 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count               = var.enable_service ? 1 : 0
  alarm_name          = "${var.name_prefix}-ecs-memory-high"
  alarm_description   = "Average ECS service memory above ${var.memory_alarm_threshold}% for 15 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.memory_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  count               = var.enable_service ? 1 : 0
  alarm_name          = "${var.name_prefix}-alb-no-healthy-targets"
  alarm_description   = "The ALB target group has no healthy targets (site is down)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.alb_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count               = var.enable_service ? 1 : 0
  alarm_name          = "${var.name_prefix}-alb-unhealthy-targets"
  alarm_description   = "At least one ALB target has been unhealthy for 3 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.alb_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count               = var.enable_service ? 1 : 0
  alarm_name          = "${var.name_prefix}-alb-target-5xx"
  alarm_description   = "Application returned 5 or more 5xx responses in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# ------------------------------------------------------------------ event notifications
resource "aws_cloudwatch_event_rule" "pipeline_failed" {
  count       = var.enable_pipeline ? 1 : 0
  name        = "${var.name_prefix}-pipeline-failed"
  description = "Notify when a pipeline execution fails"
  event_pattern = jsonencode({
    source        = ["aws.codepipeline"]
    "detail-type" = ["CodePipeline Pipeline Execution State Change"]
    detail        = { state = ["FAILED"], pipeline = [var.pipeline_name] }
  })
}

resource "aws_cloudwatch_event_target" "pipeline_failed" {
  count = var.enable_pipeline ? 1 : 0
  rule  = aws_cloudwatch_event_rule.pipeline_failed[0].name
  arn   = aws_sns_topic.alerts.arn
  input_transformer {
    input_paths    = { pipeline = "$.detail.pipeline", execution = "$.detail.execution-id", state = "$.detail.state" }
    input_template = "\"CodePipeline <pipeline> execution <execution> finished with state <state>. Open the pipeline in the AWS console to see which stage failed.\""
  }
}

resource "aws_cloudwatch_event_rule" "ecs_deployment_failed" {
  count       = var.enable_service ? 1 : 0
  name        = "${var.name_prefix}-ecs-deployment-failed"
  description = "Notify when an ECS service deployment fails (circuit breaker tripped)"
  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    resources     = [{ prefix = local.service_arn_prefix }]
    detail        = { eventName = ["SERVICE_DEPLOYMENT_FAILED"] }
  })
}

resource "aws_cloudwatch_event_target" "ecs_deployment_failed" {
  count = var.enable_service ? 1 : 0
  rule  = aws_cloudwatch_event_rule.ecs_deployment_failed[0].name
  arn   = aws_sns_topic.alerts.arn
}

# ------------------------------------------------------------------ dashboard (first 3 dashboards per account are free)
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "ECS service CPU and memory (%)"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB target health"
          region = var.aws_region
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Requests and 5xx responses"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Target response time (s)"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
    ]
  })
}

output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }
output "dashboard_name" { value = aws_cloudwatch_dashboard.this.dashboard_name }
