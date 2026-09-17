variable "container_image" {
  description = "Immutable linux/amd64 image digest, built before deployment."
  type        = string
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.container_image))
    error_message = "Use an immutable image URI ending in @sha256:<64 hex characters>."
  }
}
variable "desired_count" {
  description = "Leave zero until the one-off database migration succeeds. Maximum two tasks."
  type        = number
  default     = 0
  validation {
    condition     = contains([0, 1, 2], var.desired_count)
    error_message = "Use 0, 1, or 2 tasks."
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 3
}
resource "aws_ecs_cluster" "cloudlift" {
  name = var.project_name
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
locals {
  ecs_trust = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  db_environment = [
    { name = "DB_HOST", value = aws_db_instance.cloudlift.address },
    { name = "DB_PORT", value = "5432" },
    { name = "DB_NAME", value = "cloudlift" },
    { name = "DB_SSL", value = "true" },
    { name = "DB_CA_FILE", value = "/app/certs/us-east-1-bundle.pem" },
    { name = "AWS_REGION", value = var.aws_region }
  ]
  logs = { logDriver = "awslogs", options = {
    awslogs-group = aws_cloudwatch_log_group.api.name, awslogs-region = var.aws_region, awslogs-stream-prefix = "api"
  } }
}
data "aws_caller_identity" "current" {}
resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = local.ecs_trust
}
resource "aws_iam_role_policy" "execution" {
  role = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.api.arn}:*" }
  ] })
}
resource "aws_iam_role" "migration_execution" {
  name               = "${var.project_name}-migration-execution"
  assume_role_policy = local.ecs_trust
}
resource "aws_iam_role_policy" "migration_execution" {
  role = aws_iam_role.migration_execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.api.arn}:*" },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_db_instance.cloudlift.master_user_secret[0].secret_arn }
  ] })
}
resource "aws_iam_role" "task" {
  name               = "${var.project_name}-ecs-task"
  assume_role_policy = local.ecs_trust
}
resource "aws_iam_role_policy" "database_connect" {
  role = aws_iam_role.task.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = "rds-db:connect",
    Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.cloudlift.resource_id}/cloudlift_app"
  }] })
}
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project_name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name                   = "api", image = var.container_image, essential = true,
    readonlyRootFilesystem = true,
    portMappings           = [{ containerPort = 3000, protocol = "tcp" }],
    environment            = concat(local.db_environment, [{ name = "DB_USER", value = "cloudlift_app" }, { name = "DB_AUTH", value = "iam" }]),
    logConfiguration       = local.logs,
    healthCheck            = { command = ["CMD", "node", "-e", "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"], interval = 30, timeout = 10, retries = 3, startPeriod = 60 },
    stopTimeout            = 30
  }])
}
resource "aws_ecs_task_definition" "migration" {
  family                   = "${var.project_name}-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.migration_execution.arn
  container_definitions = jsonencode([{
    name                   = "migration", image = var.container_image, essential = true,
    readonlyRootFilesystem = true, command = ["node", "src/migrate.js"],
    environment            = concat(local.db_environment, [{ name = "DB_USER", value = "cloudlift_admin" }]),
    secrets                = [{ name = "DB_PASSWORD", valueFrom = "${aws_db_instance.cloudlift.master_user_secret[0].secret_arn}:password::" }],
    logConfiguration       = local.logs
  }])
}
resource "aws_lb" "cloudlift" {
  name               = var.project_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}
resource "aws_lb_target_group" "api" {
  name                 = "${var.project_name}-api"
  port                 = 3000
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.cloudlift.id
  deregistration_delay = 15
  health_check {
    path                = "/health"
    interval            = 15
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.cloudlift.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
resource "aws_ecs_service" "api" {
  name                               = "${var.project_name}-api"
  cluster                            = aws_ecs_cluster.cloudlift.id
  task_definition                    = aws_ecs_task_definition.api.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  availability_zone_rebalancing      = "ENABLED"
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 50
  health_check_grace_period_seconds  = 120
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.http, aws_iam_role_policy.execution, aws_iam_role_policy.database_connect]
}
output "demo" {
  value = {
    url            = "http://${aws_lb.cloudlift.dns_name}"
    cluster        = aws_ecs_cluster.cloudlift.name
    service        = aws_ecs_service.api.name
    migration_task = aws_ecs_task_definition.migration.arn
    subnets        = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_group = aws_security_group.ecs.id
    database       = aws_db_instance.cloudlift.identifier
    log_group      = aws_cloudwatch_log_group.api.name
  }
}
