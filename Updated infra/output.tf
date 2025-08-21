# Outputs for Tailored GitLab Infrastructure

# ===== RDS OUTPUTS =====
output "rds_cluster_identifier" {
  description = "RDS Aurora cluster identifier"
  value       = aws_rds_cluster.gitlab.cluster_identifier
}

output "rds_cluster_endpoint" {
  description = "RDS Aurora cluster writer endpoint"
  value       = aws_rds_cluster.gitlab.endpoint
}

output "rds_cluster_reader_endpoint" {
  description = "RDS Aurora cluster reader endpoint"
  value       = aws_rds_cluster.gitlab.reader_endpoint
}

output "rds_cluster_port" {
  description = "RDS Aurora cluster port"
  value       = aws_rds_cluster.gitlab.port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_rds_cluster.gitlab.database_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = aws_rds_cluster.gitlab.master_username
  sensitive   = true
}

output "rds_master_user_secret_arn" {
  description = "ARN of the secret containing RDS master credentials"
  value       = aws_rds_cluster.gitlab.master_user_secret[0].secret_arn
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (if enabled)"
  value       = var.enable_rds_proxy ? aws_db_proxy.gitlab[0].endpoint : null
}

output "rds_connection_endpoint" {
  description = "Best endpoint to use for connections (proxy if enabled, otherwise cluster)"
  value       = var.enable_rds_proxy ? aws_db_proxy.gitlab[0].endpoint : aws_rds_cluster.gitlab.endpoint
}

# ===== REDIS OUTPUTS =====
output "redis_replication_group_id" {
  description = "ElastiCache Redis replication group ID"
  value       = aws_elasticache_replication_group.gitlab.replication_group_id
}

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_replication_group.gitlab.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "ElastiCache Redis reader endpoint"
  value       = aws_elasticache_replication_group.gitlab.reader_endpoint_address
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_replication_group.gitlab.port
}

output "redis_auth_token_secret_arn" {
  description = "ARN of the secret containing Redis auth token"
  value       = aws_secretsmanager_secret.gitlab_redis_auth.arn
}

# ===== S3 OUTPUTS =====
output "s3_bucket_name" {
  description = "S3 bucket name for GitLab storage"
  value       = aws_s3_bucket.gitlab.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.gitlab.arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.gitlab.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.gitlab.bucket_regional_domain_name
}

# ===== KMS OUTPUTS =====
output "kms_key_id" {
  description = "KMS key ID for GitLab encryption"
  value       = aws_kms_key.gitlab.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.gitlab.arn
}

output "kms_key_alias" {
  description = "KMS key alias"
  value       = aws_kms_alias.gitlab.name
}

# ===== IAM OUTPUTS =====
output "gitlab_iam_role_arn" {
  description = "IAM role ARN for GitLab service account"
  value       = aws_iam_role.gitlab_s3_access.arn
}

output "gitlab_iam_policy_arn" {
  description = "IAM policy ARN for GitLab S3 access"
  value       = aws_iam_policy.gitlab_s3_access.arn
}

# ===== SECURITY GROUP OUTPUTS =====
output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.gitlab_rds.id
}

output "redis_security_group_id" {
  description = "Security group ID for Redis"
  value       = aws_security_group.gitlab_redis.id
}

# ===== ACM CERTIFICATE OUTPUTS =====
output "acm_certificate_arn" {
  description = "ACM certificate ARN (if created)"
  value       = var.create_acm_certificate ? aws_acm_certificate.gitlab[0].arn : null
}

output "acm_certificate_domain_validation_options" {
  description = "ACM certificate domain validation options"
  value       = var.create_acm_certificate ? aws_acm_certificate.gitlab[0].domain_validation_options : null
}

# ===== SNS OUTPUTS =====
output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.gitlab_alerts.arn
}

# ===== GITLAB CONFIGURATION SUMMARY =====
output "gitlab_configuration_summary" {
  description = "Summary of key configuration values for GitLab Helm chart"
  value = {
    # Database configuration
    database = {
      host     = var.enable_rds_proxy ? aws_db_proxy.gitlab[0].endpoint : aws_rds_cluster.gitlab.endpoint
      port     = aws_rds_cluster.gitlab.port
      database = aws_rds_cluster.gitlab.database_name
      username = aws_rds_cluster.gitlab.master_username
      password_secret_name = split("/", aws_rds_cluster.gitlab.master_user_secret[0].secret_arn)[6]
    }
    
    # Redis configuration
    redis = {
      host = aws_elasticache_replication_group.gitlab.primary_endpoint_address
      port = aws_elasticache_replication_group.gitlab.port
      auth_token_secret_name = split("/", aws_secretsmanager_secret.gitlab_redis_auth.arn)[6]
    }
    
    # Object storage configuration
    object_storage = {
      bucket_name = aws_s3_bucket.gitlab.id
      region      = data.aws_region.current.name
      iam_role_arn = aws_iam_role.gitlab_s3_access.arn
    }
    
    # TLS configuration
    tls = {
      certificate_arn = var.create_acm_certificate ? aws_acm_certificate.gitlab[0].arn : null
    }
    
    # Kubernetes configuration
    kubernetes = {
      namespace       = var.kubernetes_namespace
      service_account = var.kubernetes_service_account
    }
  }
  sensitive = true
}

# ===== HELM VALUES TEMPLATE =====
output "gitlab_helm_values_template" {
  description = "Template for GitLab Helm values with all necessary configurations"
  value = <<-EOT
    # GitLab Helm Chart Values
    # Generated by Terraform
    
    global:
      hosts:
        domain: ${var.domain_name}
        gitlab:
          name: ${var.domain_name}
        registry:
          name: registry.${var.domain_name}
      
      # Database Configuration
      psql:
        host: ${var.enable_rds_proxy ? aws_db_proxy.gitlab[0].endpoint : aws_rds_cluster.gitlab.endpoint}
        port: ${aws_rds_cluster.gitlab.port}
        database: ${aws_rds_cluster.gitlab.database_name}
        username: ${aws_rds_cluster.gitlab.master_username}
        password:
          useSecret: true
          secret: ${split("/", aws_rds_cluster.gitlab.master_user_secret[0].secret_arn)[6]}
          key: password
      
      # Redis Configuration
      redis:
        host: ${aws_elasticache_replication_group.gitlab.primary_endpoint_address}
        port: ${aws_elasticache_replication_group.gitlab.port}
        auth:
          enabled: true
          secret: ${split("/", aws_secretsmanager_secret.gitlab_redis_auth.arn)[6]}
          key: auth_token
      
      # Object Storage Configuration
      minio:
        enabled: false
      
      appConfig:
        object_store:
          enabled: true
          proxy_download: true
          storage_options: {}
          connection:
            secret: gitlab-object-storage
            key: connection
    
    # Registry Configuration
    registry:
      storage:
        secret: gitlab-object-storage
        key: registry
    
    # Service Account Configuration
    serviceAccount:
      create: true
      name: ${var.kubernetes_service_account}
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.gitlab_s3_access.arn}
    
    # Ingress Configuration
    nginx-ingress:
      enabled: true
      controller:
        service:
          annotations:
            service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
            service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${var.create_acm_certificate ? aws_acm_certificate.gitlab[0].arn : ""}
            service.beta.kubernetes.io/aws-load-balancer-ssl-ports: https
  EOT
}

# ===== NEXT STEPS =====
output "next_steps" {
  description = "Next steps for completing GitLab deployment"
  value = <<-EOT
    GitLab Infrastructure Created Successfully!
    
    Next Steps:
    1. Create Kubernetes secrets for S3 object storage configuration
    2. Install GitLab using Helm with the provided values template
    3. Configure DNS records for domain validation (if ACM certificate was created)
    4. Set up monitoring dashboards in CloudWatch
    
    Key Resources Created:
    - RDS Aurora PostgreSQL cluster with ${var.enable_rds_proxy ? "connection pooling via RDS Proxy" : "direct connections"}
    - ElastiCache Redis cluster for caching
    - S3 bucket: ${aws_s3_bucket.gitlab.id}
    - IAM role with IRSA: ${aws_iam_role.gitlab_s3_access.arn}
    - KMS key for encryption: ${aws_kms_alias.gitlab.name}
    ${var.create_acm_certificate ? "- ACM certificate for TLS" : ""}
    
    Database Endpoint: ${var.enable_rds_proxy ? aws_db_proxy.gitlab[0].endpoint : aws_rds_cluster.gitlab.endpoint}
    Redis Endpoint: ${aws_elasticache_replication_group.gitlab.primary_endpoint_address}
  EOT
}