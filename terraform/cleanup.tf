variable "cleanup_at" {
  description = "UTC RFC3339 time for the AWS-side emergency cleanup, within six hours."
  type        = string
  validation {
    condition     = can(formatdate("YYYY-MM-DD", var.cleanup_at))
    error_message = "Use a UTC RFC3339 timestamp such as 2026-09-18T02:00:00Z."
  }
}
resource "aws_iam_role" "cleanup" {
  name = "${var.project_name}-cleanup"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "scheduler.amazonaws.com" }, Action = "sts:AssumeRole",
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnEquals = { "aws:SourceArn" = "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule-group/default" } }
  }] })
}
resource "aws_iam_role_policy" "cleanup" {
  role = aws_iam_role.cleanup.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "ecs:UpdateService", Resource = aws_ecs_service.api.id },
    { Effect = "Allow", Action = "rds:DeleteDBInstance", Resource = aws_db_instance.cloudlift.arn },
    { Effect = "Allow", Action = "elasticloadbalancing:DeleteLoadBalancer", Resource = aws_lb.cloudlift.arn }
  ] })
}
locals {
  cleanup_targets = {
    api      = { action = "ecs:updateService", payload = { Cluster = aws_ecs_cluster.cloudlift.name, Service = aws_ecs_service.api.name, DesiredCount = 0 } }
    database = { action = "rds:deleteDBInstance", payload = { DBInstanceIdentifier = aws_db_instance.cloudlift.identifier, SkipFinalSnapshot = true, DeleteAutomatedBackups = true } }
    alb      = { action = "elasticloadbalancingv2:deleteLoadBalancer", payload = { LoadBalancerArn = aws_lb.cloudlift.arn } }
  }
}
resource "aws_scheduler_schedule" "cleanup" {
  for_each                     = local.cleanup_targets
  name                         = "${var.project_name}-cleanup-${each.key}"
  schedule_expression          = "at(${trimsuffix(var.cleanup_at, "Z")})"
  schedule_expression_timezone = "UTC"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:${each.value.action}"
    role_arn = aws_iam_role.cleanup.arn
    input    = jsonencode(each.value.payload)
    retry_policy {
      maximum_event_age_in_seconds = 86400
      maximum_retry_attempts       = 10
    }
  }
  depends_on = [aws_iam_role_policy.cleanup]
}
