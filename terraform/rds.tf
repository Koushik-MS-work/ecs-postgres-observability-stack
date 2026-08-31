############################################
# Secrets Manager — auto-generated DB master password
# (secret management requirement: credentials never appear in tfvars, state
#  diffs, CI logs, or the container image)
############################################

resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "RDS PostgreSQL master credentials for ${var.project_name} (${var.environment})"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_master.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
  })
}

############################################
# DB subnet group — private, no route to the internet
############################################

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

############################################
# RDS PostgreSQL instance
############################################

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-${var.environment}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version

  instance_class        = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  max_allocated_storage   = var.db_max_allocated_storage
  storage_type            = "gp3"
  storage_encrypted       = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az                = var.db_multi_az
  publicly_accessible      = false

  # --- Backup strategy ---
  backup_retention_period   = var.db_backup_retention_days
  backup_window              = "03:00-04:00"
  maintenance_window          = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot        = true
  deletion_protection           = var.db_deletion_protection
  skip_final_snapshot            = var.db_skip_final_snapshot
  final_snapshot_identifier       = var.db_skip_final_snapshot ? null : "${var.project_name}-${var.environment}-final-snapshot"

  # --- Database-level monitoring/logging ---
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled     = true
  performance_insights_retention_period = 7
  monitoring_interval                    = 60
  monitoring_role_arn                     = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true
  apply_immediately           = var.environment != "production"

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

############################################
# Additional backup layer: AWS Backup plan (point-in-time cross-checked
# snapshots independent of the RDS automated backup window)
############################################

resource "aws_backup_vault" "main" {
  name = "${var.project_name}-${var.environment}-backup-vault"
}

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-${var.environment}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "main" {
  name = "${var.project_name}-${var.environment}-backup-plan"

  rule {
    rule_name         = "daily-backups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 * * ? *)" # 05:00 UTC daily

    lifecycle {
      delete_after = 35
    }
  }
}

resource "aws_backup_selection" "rds" {
  name         = "${var.project_name}-${var.environment}-rds-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.main.id

  resources = [aws_db_instance.main.arn]
}
