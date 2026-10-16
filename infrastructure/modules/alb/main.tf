variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "container_port" { type = number }
variable "health_check_path" { type = string }
variable "deletion_protection" { type = bool }

resource "aws_lb" "this" {
  name                       = "${var.name_prefix}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [var.security_group_id]
  subnets                    = var.public_subnet_ids
  idle_timeout               = 60
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name_prefix}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate (awsvpc)
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path # readiness, so unready tasks get no traffic
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# HTTP only for the learning setup. Production: add an ACM certificate, an HTTPS listener on 443,
# and make this listener redirect to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

output "dns_name" { value = aws_lb.this.dns_name }
output "arn_suffix" { value = aws_lb.this.arn_suffix }
output "target_group_arn" { value = aws_lb_target_group.app.arn }
output "target_group_arn_suffix" { value = aws_lb_target_group.app.arn_suffix }
output "listener_arn" { value = aws_lb_listener.http.arn }
