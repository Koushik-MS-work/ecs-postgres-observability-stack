############################################
# SNS topic for alarm notifications (Slack/email fan-out)
############################################

resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-${var.environment}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_sns_topic_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_sns_topic_email
}

# To fan alarms into Slack, subscribe a Chatbot/Lambda endpoint to this same
# topic (see docs/architecture.md "Notifications" section) or point
# GitHub Actions' Slack webhook at pipeline failures directly (see
# .github/workflows/ci.yml and cd.yml).

############################################
# Infrastructure metrics — ECS service (CPU / memory)
############################################

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS service average CPU utilization above 80% for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.project_name}-${var.environment}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS service average memory utilization above 80% for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_low" {
  alarm_name          = "${var.project_name}-${var.environment}-ecs-running-tasks-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.app_min_count
  alarm_description   = "Fewer running ECS tasks than the configured minimum — possible crash loop or deployment failure"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}

############################################
# Application metrics — ALB (request rate, error rate, latency)
############################################

resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 target 5xx responses in a 1-minute period for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency_high" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "p99"
  threshold           = 2 # seconds
  alarm_description   = "p99 target response time above 2s for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "At least one unhealthy target behind the ALB"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

############################################
# Database metrics — RDS
############################################

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization above 80% for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2 GB in bytes
  alarm_description   = "RDS free storage space below 2GB"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS connection count above 80 for 3 consecutive minutes — check for connection leaks"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_memory_low" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-free-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 268435456 # 256 MB in bytes
  alarm_description   = "RDS freeable memory below 256MB for 3 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

############################################
# CloudWatch Dashboards (infrastructure + application views)
############################################

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${var.project_name}-${var.environment}-infrastructure"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "ECS CPU / Memory Utilization"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "ECS Running Task Count"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title   = "RDS CPU / Freeable Memory"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.id],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.main.id, { yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title   = "RDS Free Storage Space / Connections"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.main.id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.id, { yAxis = "right" }]
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${var.project_name}-${var.environment}-application"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "Request Count"
          view    = "timeSeries"
          region  = var.aws_region
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "Error Rate (4xx / 5xx)"
          view    = "timeSeries"
          region  = var.aws_region
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title   = "Target Response Time (p50 / p99)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p99" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title   = "Healthy / Unhealthy Host Count"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix]
          ]
        }
      },
      {
        type = "log", x = 0, y = 12, width = 24, height = 6,
        properties = {
          title  = "Recent Application Errors"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.app.name}' | fields @timestamp, @message | filter @message like /(?i)error/ | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}
