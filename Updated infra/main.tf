# GitLab on EKS - AWS Infrastructure (main.tf)
# This Terraform configuration creates all AWS resources needed for a
# highly fault-tolerant GitLab deployment on EKS

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "gitlab/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "GitLab"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster" "gitlab" {
  name = var.eks_cluster_name
}

# Local values for computed data
locals {
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.name
  cluster_name = var.eks_cluster_name
}

# Random password generation for Redis
resource "random_password" "redis_auth_token" {
  length  = 32
  special = false # Redis auth tokens don't support all special characters
}

# KMS Key for encryption
resource "aws_kms_key" "gitlab" {
  description             = "GitLab encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-key"
  })
}

resource "aws_kms_alias" "gitlab" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.gitlab.key_id
}

# SNS Topic for alerts
resource "aws_sns_topic" "gitlab_alerts" {
  name              = "${var.project_name}-alerts"
  kms_master_key_id = aws_kms_key.gitlab.key_id

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-alerts"
  })
}

resource "aws_sns_topic_subscription" "gitlab_alerts_email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.gitlab_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "gitlab_rds" {
  name              = "/aws/rds/instance/${var.project_name}-postgres/postgresql"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.gitlab.arn

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-rds-logs"
  })
}

resource "aws_cloudwatch_log_group" "gitlab_redis_slow" {
  name              = "/aws/elasticache/redis/${var.project_name}/slow-log"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.gitlab.arn

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-redis-slow-logs"
  })
}