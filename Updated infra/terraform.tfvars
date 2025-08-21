# Sample terraform.tfvars for Tailored GitLab Infrastructure (terraform.tfvars)
# Copy this file to terraform.tfvars and update with your actual values

# ===== BASIC CONFIGURATION =====
aws_region   = "us-west-2"
environment  = "prod" # dev, staging, prod
project_name = "gitlab"
owner        = "devops-team"
domain_name  = "gitlab.example.com" # Update with your actual domain

# ===== EKS CLUSTER INFORMATION =====
eks_cluster_name  = "your-eks-cluster-name"
oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/ABCD1234567890"

# ===== NETWORK CONFIGURATION =====
vpc_id                     = "vpc-0123456789abcdef0"
private_subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210", "subnet-0abcdef1234567890"]
public_subnet_ids          = ["subnet-1123456789abcdef0", "subnet-1fedcba9876543210", "subnet-1abcdef1234567890"]
eks_node_security_group_id = "sg-0123456789abcdef0"

# ===== RDS CONFIGURATION =====
rds_instance_class = "db.r6g.large" # For production
# rds_instance_class            = "db.t3.medium"        # For development/testing
rds_backup_retention_period = 7
rds_backup_window           = "03:00-04:00"
rds_maintenance_window      = "sun:04:00-sun:05:00"

# RDS Proxy Configuration (Connection Pooling)
enable_rds_proxy                       = true
rds_proxy_idle_client_timeout          = 1800 # 30 minutes
rds_proxy_max_connections_percent      = 100
rds_proxy_max_idle_connections_percent = 50
rds_proxy_connection_borrow_timeout    = 120

# ===== REDIS CONFIGURATION =====
redis_node_type = "cache.r6g.large" # For production
# redis_node_type              = "cache.t3.micro"      # For development/testing
redis_num_cache_clusters       = 3
redis_engine_version           = "7.0"
redis_snapshot_retention_limit = 5
redis_snapshot_window          = "03:00-05:00"
redis_maintenance_window       = "sun:05:00-sun:07:00"

# ===== S3 CONFIGURATION (Single Bucket) =====
s3_versioning_enabled         = true
s3_lifecycle_enabled          = true
s3_transition_to_ia_days      = 30
s3_transition_to_glacier_days = 90
s3_expiration_days            = 365 # Set to 0 to disable expiration

# ===== ACM CERTIFICATE =====
create_acm_certificate = true

# ===== SECURITY =====
allowed_cidr_blocks = ["10.0.0.0/8"] # Update with your VPC CIDR

# ===== MONITORING AND ALERTING =====
alert_email_addresses = [
  "devops-alerts@example.com",
  "sre-team@example.com"
]

# Enhanced Monitoring Configuration
enable_enhanced_monitoring    = true
cloudwatch_log_retention_days = 30

# ===== PERFORMANCE =====
enable_performance_insights           = true
performance_insights_retention_period = 7

# ===== BACKUP AND DISASTER RECOVERY =====
enable_deletion_protection = true # Disable for development environments

# ===== KUBERNETES CONFIGURATION =====
kubernetes_namespace       = "gitlab"
kubernetes_service_account = "gitlab"

# ===== ADDITIONAL TAGS =====
additional_tags = {
  "CostCenter"  = "Engineering"
  "Compliance"  = "SOC2"
  "Backup"      = "Required"
  "Environment" = "Production"
}

# ===== ENVIRONMENT-SPECIFIC EXAMPLES =====

# Development Environment Configuration:
# environment                      = "dev"
# rds_instance_class              = "db.t3.medium"
# redis_node_type                 = "cache.t3.micro"
# redis_num_cache_clusters        = 1
# enable_deletion_protection      = false
# enable_performance_insights     = false
# enable_enhanced_monitoring      = false
# cloudwatch_log_retention_days  = 7
# rds_backup_retention_period    = 1
# redis_snapshot_retention_limit = 1
# s3_expiration_days             = 30

# Staging Environment Configuration:
# environment                      = "staging"
# rds_instance_class              = "db.r6g.large"
# redis_node_type                 = "cache.r6g.medium"
# redis_num_cache_clusters        = 2
# enable_deletion_protection      = false
# enable_enhanced_monitoring      = true
# cloudwatch_log_retention_days  = 14
# rds_backup_retention_period    = 3
# redis_snapshot_retention_limit = 3

# Production Environment Configuration (High Availability):
# environment                      = "prod"
# rds_instance_class              = "db.r6g.xlarge"
# redis_node_type                 = "cache.r6g.large"
# redis_num_cache_clusters        = 3
# enable_deletion_protection      = true
# enable_performance_insights     = true
# enable_enhanced_monitoring      = true
# cloudwatch_log_retention_days  = 30
# rds_backup_retention_period    = 30
# redis_snapshot_retention_limit = 7