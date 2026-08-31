output "vpc_id" {
  description = "ID of the provisioned VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of the private application subnets"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of the private database subnets"
  value       = aws_subnet.private_db[*].id
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer — this is the app's public entry point"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Route53-compatible hosted zone ID of the ALB, for creating an alias record"
  value       = aws_lb.main.zone_id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service (used by the CD pipeline to trigger deployments)"
  value       = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository to push application images to"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "Connection endpoint of the RDS instance (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.main.address
  sensitive   = false
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch Logs group receiving application logs"
  value       = aws_cloudwatch_log_group.app.name
}

output "sns_alarm_topic_arn" {
  description = "ARN of the SNS topic that receives CloudWatch alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "infrastructure_dashboard_url" {
  description = "Console URL of the infrastructure CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure.dashboard_name}"
}

output "application_dashboard_url" {
  description = "Console URL of the application CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.application.dashboard_name}"
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault protecting the RDS instance"
  value       = aws_backup_vault.main.name
}
