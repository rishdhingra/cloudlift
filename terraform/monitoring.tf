resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${var.project_name}-target-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = aws_lb.cloudlift.arn_suffix, TargetGroup = aws_lb_target_group.api.arn_suffix }
}
resource "aws_cloudwatch_dashboard" "cloudlift" {
  dashboard_name = var.project_name
  dashboard_body = jsonencode({ widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = {
      title   = "API latency (p95)", region = var.aws_region, period = 60, stat = "p95",
      metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.cloudlift.arn_suffix, "TargetGroup", aws_lb_target_group.api.arn_suffix]]
    } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = {
      title   = "API CPU and memory", region = var.aws_region, period = 60,
      metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.cloudlift.name, "ServiceName", aws_ecs_service.api.name], ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.cloudlift.name, "ServiceName", aws_ecs_service.api.name]]
    } }
  ] })
}
