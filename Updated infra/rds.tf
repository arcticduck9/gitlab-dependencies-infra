# RDS Aurora PostgreSQL Cluster for GitLab (rds.tf)
# High availability Multi-AZ deployment with automatic failover and managed credentials

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  name  = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.additional_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Security Group for RDS
resource "aws_security_group" "gitlab_rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = var.vpc_id
  description = "Security group for GitLab RDS Aurora cluster"

  ingress {
    description     = "PostgreSQL access from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  ingress {
    description = "PostgreSQL access from private subnets"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "gitlab" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  description = "DB subnet group for GitLab Aurora cluster"

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

# RDS Aurora Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "gitlab" {
  family      = "aurora-postgresql15"
  name        = "${var.project_name}-cluster-pg"
  description = "Aurora PostgreSQL cluster parameter group for GitLab"

  # Optimized parameters for GitLab workload
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking more than 1 second
  }

  parameter {
    name  = "log_checkpoints"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "track_activity_query_size"
    value = "2048"
  }

  parameter {
    name  = "track_functions"
    value = "all"
  }

  tags = var.additional_tags

  lifecycle {
    create_before_destroy = true
  }
}

# RDS DB Parameter Group for instances
resource "aws_db_parameter_group" "gitlab" {
  family = "aurora-postgresql15"
  name   = "${var.project_name}-db-pg"

  # Instance-level parameters
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = var.additional_tags

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Aurora Cluster with Managed Credentials
resource "aws_rds_cluster" "gitlab" {
  cluster_identifier = "${var.project_name}-postgres-cluster"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  database_name      = "gitlabhq_production"

  # Use RDS managed credentials instead of manual password
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.gitlab.key_id
  master_username               = "gitlab"

  backup_retention_period         = var.rds_backup_retention_period
  preferred_backup_window         = var.rds_backup_window
  preferred_maintenance_window    = var.rds_maintenance_window
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.gitlab.name
  db_subnet_group_name            = aws_db_subnet_group.gitlab.name
  vpc_security_group_ids          = [aws_security_group.gitlab_rds.id]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.gitlab.arn
  deletion_protection             = var.enable_deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.project_name}-postgres-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Enable automatic minor version upgrades during maintenance window
  # Enable automatic minor version upgrades during maintenance window
  apply_immediately = false

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-postgres-cluster"
  })

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }

  depends_on = [
    aws_cloudwatch_log_group.gitlab_rds
  ]
}

# Aurora Writer Instance
resource "aws_rds_cluster_instance" "gitlab_writer" {
  identifier                            = "${var.project_name}-postgres-writer"
  cluster_identifier                    = aws_rds_cluster.gitlab.id
  instance_class                        = var.rds_instance_class
  engine                                = aws_rds_cluster.gitlab.engine
  engine_version                        = aws_rds_cluster.gitlab.engine_version
  db_parameter_group_name               = aws_db_parameter_group.gitlab.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.rds_monitoring_interval : 0
  monitoring_role_arn                   = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  availability_zone                     = local.azs[0]

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-postgres-writer"
    Role = "writer"
  })
}

# Aurora Reader Instance
resource "aws_rds_cluster_instance" "gitlab_reader" {
  identifier                            = "${var.project_name}-postgres-reader"
  cluster_identifier                    = aws_rds_cluster.gitlab.id
  instance_class                        = var.rds_instance_class
  engine                                = aws_rds_cluster.gitlab.engine
  engine_version                        = aws_rds_cluster.gitlab.engine_version
  db_parameter_group_name               = aws_db_parameter_group.gitlab.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.rds_monitoring_interval : 0
  monitoring_role_arn                   = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  availability_zone                     = local.azs[1]

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-postgres-reader"
    Role = "reader"
  })
}

# Aurora Reader Instance 2
resource "aws_rds_cluster_instance" "gitlab_reader_2" {
  identifier                            = "${var.project_name}-postgres-reader-2"
  cluster_identifier                    = aws_rds_cluster.gitlab.id
  instance_class                        = var.rds_instance_class
  engine                                = aws_rds_cluster.gitlab.engine
  engine_version                        = aws_rds_cluster.gitlab.engine_version
  db_parameter_group_name               = aws_db_parameter_group.gitlab.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.rds_monitoring_interval : 0
  monitoring_role_arn                   = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  availability_zone                     = local.azs[2]

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-postgres-reader-2"
    Role = "reader"
  })
}

# IAM Role for RDS Proxy
resource "aws_iam_role" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.project_name}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.additional_tags
}

# IAM Policy for RDS Proxy to access Secrets Manager
resource "aws_iam_policy" "rds_proxy_secrets" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.project_name}-rds-proxy-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = [
          aws_rds_cluster.gitlab.master_user_secret[0].secret_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.gitlab.arn
        ]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.additional_tags
}

resource "aws_iam_role_policy_attachment" "rds_proxy_secrets" {
  count      = var.enable_rds_proxy ? 1 : 0
  role       = aws_iam_role.rds_proxy[0].name
  policy_arn = aws_iam_policy.rds_proxy_secrets[0].arn
}

# RDS Proxy for connection pooling
resource "aws_db_proxy" "gitlab" {
  count = var.enable_rds_proxy ? 1 : 0

  name          = "${var.project_name}-rds-proxy"
  engine_family = "POSTGRESQL"
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_rds_cluster.gitlab.master_user_secret[0].secret_arn
  }
  role_arn               = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.gitlab_rds.id]

  # Connection pooling settings - these go in the target group, not here
  idle_client_timeout = var.rds_proxy_idle_client_timeout
  require_tls         = true

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-rds-proxy"
  })
}

# RDS Proxy Target Group
resource "aws_db_proxy_default_target_group" "gitlab" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name = aws_db_proxy.gitlab[0].name

  connection_pool_config {
    connection_borrow_timeout    = var.rds_proxy_connection_borrow_timeout
    init_query                   = "SET application_name='gitlab-proxy'"
    max_connections_percent      = var.rds_proxy_max_connections_percent
    max_idle_connections_percent = var.rds_proxy_max_idle_connections_percent
    session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
  }
}

# RDS Proxy Target - pointing to the Aurora cluster
resource "aws_db_proxy_target" "gitlab" {
  count = var.enable_rds_proxy ? 1 : 0

  db_cluster_identifier = aws_rds_cluster.gitlab.cluster_identifier
  db_proxy_name         = aws_db_proxy.gitlab[0].name
  target_group_name     = aws_db_proxy_default_target_group.gitlab[0].name
}