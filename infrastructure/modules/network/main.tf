data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs                 = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  use_private         = var.network_profile != "public"
  use_nat             = var.network_profile == "nat"
  use_endpoints       = var.network_profile == "endpoints"
  interface_endpoints = local.use_endpoints ? toset(["ecr.api", "ecr.dkr", "logs"]) : toset([])
}

# ---------------------------------------------------------------- VPC + subnets
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# Remove the permissive default rules of the default security group.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-default-sg-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = local.use_private ? var.az_count : 0
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8)
  tags              = { Name = "${var.name_prefix}-private-${local.azs[count.index]}", Tier = "private" }
}

# ---------------------------------------------------------------- routing
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = local.use_private ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = local.use_private ? var.az_count : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# ---------------------------------------------------------------- NAT (profile = nat): recurring hourly + data cost
resource "aws_eip" "nat" {
  count  = local.use_nat ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  count         = local.use_nat ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.name_prefix}-nat" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count                  = local.use_nat ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# ---------------------------------------------------------------- VPC endpoints (profile = endpoints)
resource "aws_vpc_endpoint" "s3" {
  count             = local.use_endpoints ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private[0].id]
  tags              = { Name = "${var.name_prefix}-s3-gateway" }
}

resource "aws_security_group" "endpoints" {
  count       = local.use_endpoints ? 1 : 0
  name        = "${var.name_prefix}-vpce-sg"
  description = "Interface VPC endpoints: HTTPS from ECS tasks only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_ecs" {
  count                        = local.use_endpoints ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from ECS tasks"
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_endpoints
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${var.name_prefix}-${replace(each.key, ".", "-")}-vpce" }
}

# ---------------------------------------------------------------- security groups
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public HTTP into the load balancer"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.name_prefix}-ecs-sg"
  description = "ECS tasks: app traffic from the ALB only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-ecs-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(var.allowed_ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP (learning setup; use HTTPS in production)"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  description                  = "To ECS tasks"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  description                  = "App traffic from the ALB only"
}

# Outbound HTTPS to the internet (public / nat profiles): ECR image pull, CloudWatch Logs.
resource "aws_vpc_security_group_egress_rule" "ecs_https_internet" {
  count             = local.use_endpoints ? 0 : 1
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to AWS service endpoints"
}

# Outbound HTTPS to interface endpoints + S3 (image layers are stored in S3) (endpoints profile).
resource "aws_vpc_security_group_egress_rule" "ecs_to_endpoints" {
  count                        = local.use_endpoints ? 1 : 0
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.endpoints[0].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS to interface VPC endpoints"
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_s3" {
  count             = local.use_endpoints ? 1 : 0
  security_group_id = aws_security_group.ecs.id
  prefix_list_id    = aws_vpc_endpoint.s3[0].prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to S3 via gateway endpoint"
}
