variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "vpc_cidr" { type = string }
variable "az_count" {
  type = number
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (an ALB needs at least two Availability Zones)."
  }
}
variable "network_profile" {
  type        = string
  description = "public | nat | endpoints (see docs/architecture.md for cost trade-offs)"
  validation {
    condition     = contains(["public", "nat", "endpoints"], var.network_profile)
    error_message = "network_profile must be one of: public, nat, endpoints."
  }
}
variable "container_port" { type = number }
variable "allowed_ingress_cidrs" { type = list(string) }
