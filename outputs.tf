# outputs.tf - Outputs for GitLab Dependencies

# Network Load Balancer Outputs
output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.gitlab.dns_name
}

output "nlb_zone_id" {
  description = "Zone ID of the Network Load Balancer"
  value       = aws_lb.gitlab.zone_id
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.gitlab.arn
}

# Target Groups for EKS integration
output "target_group_arns" {
  description = "ARNs of the target groups for EKS LoadBalancer services"
  value = {
    for name, tg in aws_lb_target_group.gitlab : name => tg.arn
  }
}

# PostgreSQL RDS Outputs
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint for GitLab database connection"
  value       = aws_db_instance.gitlab.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.gitlab.port
}

output "rds_database_name" {
  description = "RDS database name (gitlabhq_production)"
  value       = aws_db_instance.gitlab.db_name
}

output "rds_username" {
  description = "RDS master username"
  value       = aws_db_instance.gitlab.username
}

output "rds_password" {
  description = "RDS master password (sensitive)"
  value       = random_password.db_password.result
  sensitive   = true
}

output "rds_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.gitlab.arn
}

# Redis ElastiCache Outputs
output "redis_primary_endpoint" {
  description = "Redis primary endpoint for GitLab cache connection"
  value       = aws_elasticache_replication_group.gitlab.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint (if applicable)"
  value       = aws_elasticache_replication_group.gitlab.reader_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.gitlab.port
}

output "redis_auth_token" {
  description = "Redis authentication token (sensitive)"
  value       = random_password.redis_auth_token.result
  sensitive   = true
}

# Security Groups for reference
output "security_group_ids" {
  description = "Security group IDs created for the resources"
  value = {
    rds   = aws_security_group.rds.id
    redis = aws_security_group.redis.id
  }
}

# Connection strings for easy integration
output "postgresql_connection_string" {
  description = "PostgreSQL connection string format (without password for security)"
  value       = "postgresql://${aws_db_instance.gitlab.username}:PASSWORD@${aws_db_instance.gitlab.endpoint}:${aws_db_instance.gitlab.port}/${aws_db_instance.gitlab.db_name}"
  sensitive   = false
}

output "redis_connection_string" {
  description = "Redis connection string format (without auth token for security)"
  value       = "redis://AUTH_TOKEN@${aws_elasticache_replication_group.gitlab.primary_endpoint_address}:${aws_elasticache_replication_group.gitlab.port}"
  sensitive   = false
}

# Summary of all critical information
output "gitlab_infrastructure_summary" {
  description = "Summary of all GitLab infrastructure components"
  value = {
    load_balancer = {
      dns_name = aws_lb.gitlab.dns_name
      type     = "Network Load Balancer"
      scheme   = "internet-facing"
    }
    database = {
      endpoint = aws_db_instance.gitlab.endpoint
      port     = aws_db_instance.gitlab.port
      engine   = "PostgreSQL ${var.postgres_version}"
      multi_az = var.multi_az_enabled
    }
    cache = {
      primary_endpoint = aws_elasticache_replication_group.gitlab.primary_endpoint_address
      port             = aws_elasticache_replication_group.gitlab.port
      engine           = "Redis ${var.redis_version}"
      multi_az         = var.redis_multi_az_enabled
    }
  }
}