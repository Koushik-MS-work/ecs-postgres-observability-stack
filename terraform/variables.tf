############################################
# General
############################################

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "devops-project"
}

variable "environment" {
  description = "Deployment environment (e.g. staging, production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be one of: staging, production."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

############################################
# Networking
############################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private database subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT gateway for private subnet egress. Disable in cost-sensitive sandboxes."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ (cheaper, less resilient). Recommended true for staging, false for production."
  type        = bool
  default     = true
}

############################################
# Application / ECS
############################################

variable "container_image" {
  description = "Container image (repo:tag) to deploy. Overridden by the CD pipeline on each deploy."
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:stable"
}

variable "container_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 3000
}

variable "app_task_cpu" {
  description = "Fargate task CPU units (256 = .25 vCPU)"
  type        = number
  default     = 256
}

variable "app_task_memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 512
}

variable "app_desired_count" {
  description = "Desired number of running application tasks"
  type        = number
  default     = 2
}

variable "app_min_count" {
  description = "Minimum tasks for autoscaling"
  type        = number
  default     = 2
}

variable "app_max_count" {
  description = "Maximum tasks for autoscaling"
  type        = number
  default     = 6
}

variable "health_check_path" {
  description = "HTTP path the ALB uses for target group health checks"
  type        = string
  default     = "/health"
}

############################################
# Database (RDS PostgreSQL)
############################################

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Upper bound (GB) for RDS storage autoscaling"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for RDS. The password is auto-generated and stored in Secrets Manager, never in state as a variable."
  type        = string
  default     = "app_admin"
}

variable "db_multi_az" {
  description = "Whether to deploy RDS in Multi-AZ for high availability. Recommended true for production."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automated RDS backups"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on RDS destroy (set false for production)"
  type        = bool
  default     = true
}

############################################
# Monitoring / Alerting
############################################

variable "alarm_sns_topic_email" {
  description = "Email address subscribed to CloudWatch alarm notifications. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 30
}
