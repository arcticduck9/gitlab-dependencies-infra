# terraform.tfvars - Configuration for GitLab Dependencies

# Basic Configuration
aws_region   = "us-east-1"
cluster_name = "gitlab-nonprod"
vpc_name     = "defaultvpc" # Replace with your actual VPC name

# Common Tags
common_tags = {
  Project     = "GitLab"
  Environment = "nonprod"
  Team        = "DevOps"
  ManagedBy   = "Terraform"
}

# PostgreSQL RDS Configuration
postgres_version         = "16.8"         # GitLab recommended version
db_instance_class        = "db.t4g.micro" # Adjust based on your needs
db_allocated_storage     = 20             # Initial storage in GB
db_max_allocated_storage = 20             # Max auto-scaling storage in GB
backup_retention_period  = 7              # Backup retention in days
multi_az_enabled         = false          # Enable for production

# Redis ElastiCache Configuration
redis_version                    = "7.0"             # GitLab recommended version
redis_node_type                  = "cache.t4g.micro" # Adjust based on your needs
redis_num_cache_nodes            = 2                 # Number of Redis nodes
redis_snapshot_retention_limit   = 5                 # Snapshot retention in days
redis_automatic_failover_enabled = true              # Enable for production
redis_multi_az_enabled           = false             # Enable for production

# Security Configuration
deletion_protection = true # Enable for production to prevent accidental deletion