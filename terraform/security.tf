# Network boundaries for the planned ALB -> API -> PostgreSQL deployment.
# This file creates no running compute, database, or load balancer.
variable "allowed_http_cidrs" {
  description = "IPv4 CIDRs allowed to reach the demo over HTTP. Empty keeps ingress closed. Use only test data until HTTPS and authentication are configured."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_http_cidrs : can(cidrnetmask(cidr))])
    error_message = "Each entry must be a valid IPv4 CIDR."
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Entry point for the CloudLift demo"
  vpc_id      = aws_vpc.cloudlift.id
  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "CloudLift API accepts traffic only from its load balancer"
  vpc_id      = aws_vpc.cloudlift.id
  tags = {
    Name    = "${var.project_name}-ecs-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "database" {
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL accepts traffic only from the CloudLift API"
  vpc_id      = aws_vpc.cloudlift.id
  tags = {
    Name    = "${var.project_name}-db-sg"
    Project = var.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each          = var.allowed_http_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from an explicitly allowed demo client"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  description                  = "API requests and health checks"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "API traffic only from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "api_outbound" {
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS image pulls and AWS service access"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "database_from_api" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.ecs.id
  description                  = "PostgreSQL only from the API"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "api_to_database" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.database.id
  description                  = "PostgreSQL only to the project database"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
