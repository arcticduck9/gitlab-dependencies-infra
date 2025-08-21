# S3 Bucket for GitLab Object Storage (s3.tf)
# Single bucket with proper versioning, lifecycle, and security

# Create S3 bucket for GitLab
resource "aws_s3_bucket" "gitlab" {
  bucket        = "${var.project_name}-${var.environment}-storage"
  force_destroy = var.environment != "prod" # Allow force destroy in non-prod environments

  tags = merge(var.additional_tags, {
    Name        = "${var.project_name}-storage"
    Purpose     = "GitLab object storage"
    Environment = var.environment
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "gitlab" {
  bucket = aws_s3_bucket.gitlab.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab" {
  bucket = aws_s3_bucket.gitlab.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.gitlab.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "gitlab" {
  bucket = aws_s3_bucket.gitlab.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "gitlab" {
  count = var.s3_lifecycle_enabled ? 1 : 0

  bucket     = aws_s3_bucket.gitlab.id
  depends_on = [aws_s3_bucket_versioning.gitlab]

  rule {
    id     = "gitlab_lifecycle"
    status = "Enabled"

    # Add explicit filter instead of no filter
    filter {
      prefix = ""
    }

    # Current version lifecycle
    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Expire objects after specified days (if enabled)
    dynamic "expiration" {
      for_each = var.s3_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_expiration_days
      }
    }

    # Non-current version lifecycle (for versioned buckets)
    dynamic "noncurrent_version_transition" {
      for_each = var.s3_versioning_enabled ? [1] : []
      content {
        noncurrent_days = var.s3_transition_to_ia_days
        storage_class   = "STANDARD_IA"
      }
    }

    dynamic "noncurrent_version_transition" {
      for_each = var.s3_versioning_enabled ? [1] : []
      content {
        noncurrent_days = var.s3_transition_to_glacier_days
        storage_class   = "GLACIER"
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.s3_versioning_enabled && var.s3_expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = var.s3_expiration_days
      }
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Special rule for backup data - longer retention
  rule {
    id     = "backup-retention"
    status = "Enabled"

    filter {
      prefix = "gitlab-backups/"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # Keep backups for 7 years
    expiration {
      days = 2555
    }
  }
}

# S3 Bucket Notification for backup monitoring
resource "aws_s3_bucket_notification" "gitlab_backup_notification" {
  bucket = aws_s3_bucket.gitlab.id

  topic {
    topic_arn     = aws_sns_topic.gitlab_alerts.arn
    events        = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix = "gitlab-backups/"
  }

  depends_on = [aws_sns_topic_policy.gitlab_alerts_s3]
}

# S3 Bucket CORS Configuration for web access
resource "aws_s3_bucket_cors_configuration" "gitlab" {
  bucket = aws_s3_bucket.gitlab.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${var.domain_name}"]
    expose_headers  = ["ETag", "x-amz-meta-*"]
    max_age_seconds = 3000
  }
}

# SNS Topic Policy to allow S3 to publish
resource "aws_sns_topic_policy" "gitlab_alerts_s3" {
  arn = aws_sns_topic.gitlab_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.gitlab_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}