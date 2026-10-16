output "cluster_name" { value = aws_ecs_cluster.this.name }
output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "service_name" { value = var.service_name }
output "log_group_name" { value = aws_cloudwatch_log_group.app.name }
output "execution_role_arn" { value = aws_iam_role.task_execution.arn }
output "task_role_arn" { value = aws_iam_role.task.arn }
output "task_definition_family" { value = "${var.name_prefix}-task" }
