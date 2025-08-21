# ElastiCache Redis Cluster for GitLab (elasticache.tf)
# High availability Multi-AZ deployment with automatic failover

# Security Group for ElastiCache
resource "aws_security_group" "gitlab_redis" {
  name_prefix = "${var.project_name}-redis-"
  vpc_id      = var.vpc_id
  description = "Security group for GitLab ElastiCache Redis cluster"

  ingress {
    description     = "Redis access from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  ingress {
    description = "Redis access from private subnets"
    from_port   = 6379
    to_port     = 6379
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
    Name = "${var.project_name}-redis-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "gitlab" {
  name       = "${var.project_name}-cache-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-cache-subnet-group"
  })
}

# ElastiCache Parameter Group for Redis 7.0
resource "aws_elasticache_parameter_group" "gitlab_redis" {
  name   = "${var.project_name}-redis-params"
  family = "redis7"

  # Optimize for GitLab workload
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  parameter {
    name  = "maxclients"
    value = "20000"
  }

  # Enable slow log for debugging
  parameter {
    name  = "slowlog-log-slower-than"
    value = "10000" # Log commands taking more than 10ms
  }

  parameter {
    name  = "slowlog-max-len"
    value = "1024"
  }

  tags = var.additional_tags

  lifecycle {
    create_before_destroy = true
  }
}

# ElastiCache User for authentication
resource "aws_elasticache_user" "gitlab_redis" {
  user_id       = "${var.project_name}-redis-user"
  user_name     = "gitlab-user"
  access_string = "on ~* +@all"
  engine        = "REDIS"
  passwords     = [random_password.redis_auth_token.result]

  tags = var.additional_tags

  lifecycle {
    ignore_changes = [passwords]
  }
}

# ElastiCache User Group
resource "aws_elasticache_user_group" "gitlab_redis" {
  engine        = "REDIS"
  user_group_id = "${var.project_name}-redis-user-group"
  user_ids      = [aws_elasticache_user.gitlab_redis.user_id]

  tags = var.additional_tags

  depends_on = [aws_elasticache_user.gitlab_redis]
}

# ElastiCache Replication Group with Multi-AZ
resource "aws_elasticache_replication_group" "gitlab" {
  replication_group_id         = "${var.project_name}-redis"
  description                  = "GitLab Redis cluster with failover"
  
  # Cluster Configuration
  num_cache_clusters           = var.redis_num_cache_clusters
  node_type                   = var.redis_node_type
  engine                      = "redis"
  engine_version              = var.redis_engine_version
  parameter_group_name        = aws_elasticache_parameter_group.gitlab_redis.name
  port                        = 6379
  
  # High Availability Configuration
  multi_az_enabled            = true
  automatic_failover_enabled  = true
  preferred_cache_cluster_azs = local.azs

  # Network Configuration
  subnet_group_name          = aws_elasticache_subnet_group.gitlab.name
  security_group_ids         = [aws_security_group.gitlab_redis.id]

  # Authentication and Security
  auth_token                 = random_password.redis_auth_token.result
  auth_token_update_strategy = "ROTATE"
  user_group_ids            = [aws_elasticache_user_group.gitlab_redis.user_group_id]
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                = aws_kms_key.gitlab.arn

  # Backup Configuration
  snapshot_retention_limit   = var.redis_snapshot_retention_limit
  snapshot_window           = var.redis_snapshot_window
  final_snapshot_identifier = "${var.project_name}-redis-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Maintenance Configuration
  maintenance_window        = var.redis_maintenance_window
  auto_minor_version_upgrade = true
  apply_immediately         = false

  # Logging Configuration
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.gitlab_redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format      = "text"
    log_type        = "slow-log"
  }

  # Notification Configuration
  notification_topic_arn = aws_sns_topic.gitlab_alerts.arn

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-redis"
  })

  lifecycle {
    ignore_changes = [
      auth_token,
      final_snapshot_identifier
    ]
  }

  depends_on = [
    aws_cloudwatch_log_group.gitlab_redis_slow
  ]
}

# Store Redis auth token in AWS Secrets Manager
resource "aws_secretsmanager_secret" "gitlab_redis_password" {
  name                    = "${var.project_name}/redis/auth-token"
  description            = "GitLab Redis auth token"
  kms_key_id            = aws_kms_key.gitlab.key_id
  recovery_window_in_days = var.environment == "prod" ? 7 : 0

  tags = var.additional_tags
}

resource "aws_secretsmanager_secret_version" "gitlab_redis_password" {
  secret_id = aws_secretsmanager_secret.gitlab_redis_password.id
  secret_string = jsonencode({
    auth_token              = random_password.redis_auth_token.result
    primary_endpoint        = aws_elasticache_replication_group.gitlab.primary_endpoint_address
    reader_endpoint_address = aws_elasticache_replication_group.gitlab.reader_endpoint_address
    port                   = aws_elasticache_replication_group.gitlab.port
    configuration_endpoint  = aws_elasticache_replication_group.gitlab.configuration_endpoint_address
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}