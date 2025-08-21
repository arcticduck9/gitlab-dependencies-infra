# Variables for Tailored GitLab Infrastructure (variables.tf)

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Name of the project (used in resource naming)"
  type        = string
  default     = "gitlab"
}

variable "owner" {
  description = "Owner of the resources (team or individual)"
  type        = string
  default     = "devops"
}

variable "domain_name" {
  description = "Domain name for GitLab (e.g., gitlab.example.com)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster (for IRSA)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for database and cache subnets"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for load balancers"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS nodes"
  type        = string
}

# RDS Configuration
variable "rds_instance_class" {
  description = "Instance class for RDS Aurora instances"
  type        = string
  default     = "db.r6g.large"
}

variable "rds_backup_retention_period" {
  description = "Backup retention period in days for RDS"
  type        = number
  default     = 7
}

variable "rds_backup_window" {
  description = "Preferred backup window for RDS"
  type        = string
  default     = "03:00-04:00"
}

variable "rds_maintenance_window" {
  description = "Preferred maintenance window for RDS"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS cluster"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for RDS"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Retention period for Performance Insights data (days)"
  type        = number
  default     = 7
}

# RDS Enhanced Monitoring
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS"
  type        = bool
  default     = true
}

variable "rds_monitoring_interval" {
  description = "Enhanced monitoring interval for RDS (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60
}

# RDS Proxy Configuration
variable "enable_rds_proxy" {
  description = "Enable RDS Proxy for connection pooling"
  type        = bool
  default     = true
}

variable "rds_proxy_idle_client_timeout" {
  description = "The number of seconds that a connection to the proxy can be inactive"
  type        = number
  default     = 1800 # 30 minutes
}

variable "rds_proxy_max_connections_percent" {
  description = "The maximum size of the connection pool for each target"
  type        = number
  default     = 100
}

variable "rds_proxy_max_idle_connections_percent" {
  description = "Controls how actively the proxy closes idle database connections"
  type        = number
  default     = 50
}

variable "rds_proxy_connection_borrow_timeout" {
  description = "The number of seconds for a proxy to wait for a connection"
  type        = number
  default     = 120
}

# ElastiCache Configuration
variable "redis_node_type" {
  description = "Node type for ElastiCache Redis cluster"
  type        = string
  default     = "cache.r6g.large"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters in the replication group"
  type        = number
  default     = 3
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days for which ElastiCache retains automatic snapshots"
  type        = number
  default     = 5
}

variable "redis_snapshot_window" {
  description = "Time range during which snapshots are taken"
  type        = string
  default     = "03:00-05:00"
}

variable "redis_maintenance_window" {
  description = "Maintenance window for ElastiCache"
  type        = string
  default     = "sun:05:00-sun:07:00"
}

# S3 Configuration (Single Bucket)
variable "s3_versioning_enabled" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Days to transition objects to Infrequent Access storage class"
  type        = number
  default     = 30
}

variable "s3_transition_to_glacier_days" {
  description = "Days to transition objects to Glacier storage class"
  type        = number
  default     = 90
}

variable "s3_expiration_days" {
  description = "Days to expire objects (0 = disabled)"
  type        = number
  default     = 365
}

# ACM Certificate
variable "create_acm_certificate" {
  description = "Whether to create an ACM certificate"
  type        = bool
  default     = true
}

# Kubernetes Configuration
variable "kubernetes_namespace" {
  description = "Kubernetes namespace where GitLab will be deployed"
  type        = string
  default     = "gitlab"
}

variable "kubernetes_service_account" {
  description = "Kubernetes service account name for GitLab"
  type        = string
  default     = "gitlab"
}

# Security
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access RDS and ElastiCache"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# Monitoring and Alerting
variable "alert_email_addresses" {
  description = "List of email addresses for CloudWatch alarms"
  type        = list(string)
  default     = []
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Retention period for CloudWatch logs in days"
  type        = number
  default     = 30
}