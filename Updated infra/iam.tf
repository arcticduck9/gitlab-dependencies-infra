# IAM Roles and Policies for GitLab (iam.tf)
# Includes IRSA (IAM Roles for Service Accounts) setup

# IAM Role for GitLab Service Account (IRSA)
resource "aws_iam_role" "gitlab_s3_access" {
  name = "${var.project_name}-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-s3-access-role"
  })
}

# IAM Policy for S3 access
resource "aws_iam_policy" "gitlab_s3_access" {
  name        = "${var.project_name}-s3-access-policy"
  description = "GitLab S3 access policy for object storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 bucket operations
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetBucketLogging",
          "s3:GetBucketNotification",
          "s3:GetBucketTagging"
        ]
        Resource = aws_s3_bucket.gitlab.arn
      },
      # S3 object operations
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:RestoreObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.gitlab.arn}/*"
      },
      # KMS key operations for S3 encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = [
          aws_kms_key.gitlab.arn
        ]
      },
      # CloudWatch logs for debugging
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/gitlab/*"
      }
    ]
  })

  tags = var.additional_tags
}

# Attach S3 policy to GitLab role
resource "aws_iam_role_policy_attachment" "gitlab_s3_access" {
  policy_arn = aws_iam_policy.gitlab_s3_access.arn
  role       = aws_iam_role.gitlab_s3_access.name
}

# IAM Role for GitLab Registry Service Account
resource "aws_iam_role" "gitlab_registry_s3_access" {
  name = "${var.project_name}-registry-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${var.project_name}-registry"
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-registry-s3-access-role"
  })
}

# IAM Policy for Registry S3 access (restricted to registry prefix only)
resource "aws_iam_policy" "gitlab_registry_s3_access" {
  name        = "${var.project_name}-registry-s3-access-policy"
  description = "GitLab Registry S3 access policy for container registry"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Registry bucket operations
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = aws_s3_bucket.gitlab.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["gitlab-registry/*"]
          }
        }
      },
      # Registry object operations
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.gitlab.arn}/gitlab-registry/*"
      },
      # KMS key operations for registry encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.gitlab.arn
      }
    ]
  })

  tags = var.additional_tags
}

# Attach Registry S3 policy to Registry role
resource "aws_iam_role_policy_attachment" "gitlab_registry_s3_access" {
  policy_arn = aws_iam_policy.gitlab_registry_s3_access.arn
  role       = aws_iam_role.gitlab_registry_s3_access.name
}

# IAM Role for GitLab Runner Service Account
resource "aws_iam_role" "gitlab_runner_s3_access" {
  name = "${var.project_name}-runner-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${var.project_name}-gitlab-runner"
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-runner-s3-access-role"
  })
}

# IAM Policy for GitLab Runner S3 cache access
resource "aws_iam_policy" "gitlab_runner_s3_access" {
  name        = "${var.project_name}-runner-s3-access-policy"
  description = "GitLab Runner S3 access policy for cache storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Runner cache bucket operations
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.gitlab.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["gitlab-runner-cache/*"]
          }
        }
      },
      # Runner cache object operations
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.gitlab.arn}/gitlab-runner-cache/*"
      },
      # KMS key operations for runner cache encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.gitlab.arn
      }
    ]
  })

  tags = var.additional_tags
}

# Attach Runner S3 policy to Runner role
resource "aws_iam_role_policy_attachment" "gitlab_runner_s3_access" {
  policy_arn = aws_iam_policy.gitlab_runner_s3_access.arn
  role       = aws_iam_role.gitlab_runner_s3_access.name
}

# IAM Role for GitLab Toolbox (backups) Service Account
resource "aws_iam_role" "gitlab_toolbox_s3_access" {
  name = "${var.project_name}-toolbox-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${var.project_name}-toolbox"
            "${replace(data.aws_eks_cluster.gitlab.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-toolbox-s3-access-role"
  })
}

# IAM Policy for GitLab Toolbox S3 access (backups and restores)
resource "aws_iam_policy" "gitlab_toolbox_s3_access" {
  name        = "${var.project_name}-toolbox-s3-access-policy"
  description = "GitLab Toolbox S3 access policy for backups and restores"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Toolbox backup bucket operations
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.gitlab.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["gitlab-backups/*"]
          }
        }
      },
      # Toolbox backup object operations
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:RestoreObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.gitlab.arn}/gitlab-backups/*"
      },
      # Additional permissions for backup verification and listing
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectAcl",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectTagging",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.gitlab.arn}/gitlab-backups/*"
      },
      # KMS key operations for toolbox backup encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.gitlab.arn
      },
      # CloudWatch logs for backup monitoring
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/gitlab/toolbox/*"
      }
    ]
  })

  tags = var.additional_tags
}

# Attach Toolbox S3 policy to Toolbox role
resource "aws_iam_role_policy_attachment" "gitlab_toolbox_s3_access" {
  policy_arn = aws_iam_policy.gitlab_toolbox_s3_access.arn
  role       = aws_iam_role.gitlab_toolbox_s3_access.name
}