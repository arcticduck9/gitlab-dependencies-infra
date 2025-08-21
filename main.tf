# main.tf - GitLab Dependencies Infrastructure (NLB, RDS PostgreSQL, Redis ElastiCache)
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources for existing VPC and subnets
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# Get all subnets in the VPC
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# For default VPC or VPCs without proper private subnets,
# we'll use all available subnets but create security groups to restrict access
locals {
  subnet_ids = data.aws_subnets.all.ids
  # Target group configurations
  target_groups = {
    http = {
      port              = 80
      health_check_port = "traffic-port"
      health_check_path = "/-/health"
      protocol          = "HTTP"
    }
    https = {
      port              = 443
      health_check_port = "80"
      health_check_path = "/-/health"
      protocol          = "HTTP"
    }
    ssh = {
      port              = 22
      health_check_port = "22"
      health_check_path = null
      protocol          = "TCP"
    }
  }
}

# Random password for RDS
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:;,.<>?~"
}

# Random password for Redis auth token
resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

# Security Groups
resource "aws_security_group" "rds" {
  name_prefix = "${var.cluster_name}-rds-"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-rds-sg"
  })
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_name}-redis-"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-redis-sg"
  })
}

# RDS Subnet Group
resource "aws_db_subnet_group" "gitlab" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = local.subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-db-subnet-group"
  })
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "gitlab" {
  name       = "${var.cluster_name}-cache-subnet-group"
  subnet_ids = local.subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-cache-subnet-group"
  })
}

resource "aws_db_parameter_group" "gitlab" {
  family = "postgres${split(".", var.postgres_version)[0]}"
  name   = "${var.cluster_name}-postgres-params"

  # Only keep dynamic parameters
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgres-params"
  })
  
  lifecycle {
    create_before_destroy = false
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "gitlab" {
  identifier = "${var.cluster_name}-postgresql"

  # Engine configuration
  engine                = "postgres"
  engine_version        = var.postgres_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = "gitlabhq_production"
  username = "gitlab"
  password = random_password.db_password.result

  # Network configuration
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.gitlab.name
  publicly_accessible    = false
  port                   = 5432

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:00-Sun:05:00"

  # High Availability
  multi_az = var.multi_az_enabled

  # Performance Insights
  performance_insights_enabled = true

  # Parameter group
  parameter_group_name = aws_db_parameter_group.gitlab.name

  # Deletion protection
  #deletion_protection = var.deletion_protection
  #skip_final_snapshot = !var.deletion_protection
  skip_final_snapshot = true

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgresql"
  })

  depends_on = [
    aws_db_subnet_group.gitlab,
    aws_security_group.rds
  ]
}

# ElastiCache Parameter Group for GitLab
resource "aws_elasticache_parameter_group" "gitlab" {
  family = "redis${split(".", var.redis_version)[0]}"
  name   = "${var.cluster_name}-redis-params"

  # GitLab recommended Redis parameters
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-redis-params"
  })
}

# ElastiCache Redis Replication Group
resource "aws_elasticache_replication_group" "gitlab" {
  replication_group_id = "${var.cluster_name}-redis"
  description          = "GitLab Redis cluster"

  # Redis configuration
  engine               = "redis"
  engine_version       = var.redis_version
  node_type            = var.redis_node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.gitlab.name

  # Cluster configuration
  num_cache_clusters = var.redis_num_cache_nodes

  # Network configuration
  subnet_group_name  = aws_elasticache_subnet_group.gitlab.name
  security_group_ids = [aws_security_group.redis.id]

  # Security
  auth_token                 = random_password.redis_auth_token.result
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  # Backup configuration
  snapshot_retention_limit = var.redis_snapshot_retention_limit
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "Sun:05:00-Sun:06:00"

  # Automatic failover
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  multi_az_enabled           = var.redis_multi_az_enabled

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-redis"
  })

  depends_on = [
    aws_elasticache_subnet_group.gitlab,
    aws_security_group.redis
  ]
}

# Network Load Balancer
resource "aws_lb" "gitlab" {
  name               = "${var.cluster_name}-nlb"
  load_balancer_type = "network"
  internal           = false # false = internet-facing, true = internal
  subnets            = local.subnet_ids

  #enable_deletion_protection = var.deletion_protection
  enable_deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-nlb"
  })
}

# NLB Target Groups - simplified with for_each
resource "aws_lb_target_group" "gitlab" {
  for_each = local.target_groups

  name     = "${var.cluster_name}-${each.key}"
  port     = each.value.port
  protocol = "TCP"
  vpc_id   = data.aws_vpc.existing.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = each.value.protocol == "HTTP" ? "200" : null
    path                = each.value.health_check_path
    port                = each.value.health_check_port
    protocol            = each.value.protocol
    timeout             = 10
    unhealthy_threshold = 2
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-${each.key}-tg"
  })
}

# NLB Listeners
resource "aws_lb_listener" "gitlab_http" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab["http"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-http-listener"
  })
}

resource "aws_lb_listener" "gitlab_https" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab["https"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-https-listener"
  })
}

resource "aws_lb_listener" "gitlab_ssh" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab["ssh"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-ssh-listener"
  })
}