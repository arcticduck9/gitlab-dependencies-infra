# CloudWatch Monitoring and ACM Certificate for GitLab (cloudwatch.tf)

# ACM Certificate for GitLab domain
resource "aws_acm_certificate" "gitlab" {
  count = var.create_acm_certificate ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain_name}"  # Wildcard for subdomains like registry.domain.com
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-certificate"
  })
}

# Route 53 hosted zone data (if using Route 53 for DNS validation)
data "aws_route53_zone" "gitlab" {
  count = var.create_acm_certificate ? 1 : 0
  name  = var.domain_name
}

# ACM Certificate validation using Route 53
resource "aws_route53_record" "gitlab_cert_validation" {
  for_each = var.create_acm_certificate ? {
    for dvo in aws_acm_certificate.gitlab[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.gitlab[0].zone_id
}

# ACM Certificate validation
resource "aws_acm_certificate_validation" "gitlab" {
  count = var.create_acm_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.gitlab[0].arn
  validation_record_fqdns = [for record in aws_route53_record.gitlab_cert_validation : record.fqdn]

  timeouts {
    create = "5m"
  }
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  alarm_name          = "${var.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.gitlab.cluster_identifier
  }

  tags = var.additional_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_database_connections" {
  alarm_name          = "${var.project_name}-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.gitlab.cluster_identifier
  }

  tags = var.additional_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_read_latency" {
  alarm_name          = "${var.project_name}-rds-high-read-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.2"  # 200ms
  alarm_description   = "This metric monitors RDS read latency"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.gitlab.cluster_identifier
  }

  tags = var.additional_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_write_latency" {
  alarm_name          = "${var.project_name}-rds-high-write-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.2"  # 200ms
  alarm_description   = "This metric monitors RDS write latency"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.gitlab.cluster_identifier
  }

  tags = var.additional_tags
}

# CloudWatch Alarms for ElastiCache Redis
resource "aws_cloudwatch_metric_alarm" "redis_cpu_utilization" {
  for_each = toset(["001", "002", "003"])  # For 3 Redis nodes

  alarm_name          = "${var.project_name}-redis-${each.key}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Redis CPU utilization for node ${each.key}"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    CacheClusterId = "${aws_elasticache_replication_group.gitlab.replication_group_id}-${each.key}"
  }

  tags = var.additional_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory_utilization" {
  for_each = toset(["001", "002", "003"])  # For 3 Redis nodes

  alarm_name          = "${var.project_name}-redis-${each.key}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors Redis memory utilization for node ${each.key}"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    CacheClusterId = "${aws_elasticache_replication_group.gitlab.replication_group_id}-${each.key}"
  }

  tags = var.additional_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  for_each = toset(["001", "002", "003"])  # For 3 Redis nodes

  alarm_name          = "${var.project_name}-redis-${each.key}-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "This metric monitors Redis evictions for node ${each.key}"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]
  ok_actions          = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    CacheClusterId = "${aws_elasticache_replication_group.gitlab.replication_group_id}-${each.key}"
  }

  tags = var.additional_tags
}

# CloudWatch Alarm for S3 Storage
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  alarm_name          = "${var.project_name}-s3-large-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400"  # Daily
  statistic           = "Average"
  threshold           = "107374182400"  # 100GB in bytes
  alarm_description   = "This metric monitors S3 bucket size"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    BucketName  = aws_s3_bucket.gitlab.id
    StorageType = "StandardStorage"
  }

  tags = var.additional_tags
}

# CloudWatch Alarm for S3 Request Errors
resource "aws_cloudwatch_metric_alarm" "s3_4xx_errors" {
  alarm_name          = "${var.project_name}-s3-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors S3 4xx errors"
  alarm_actions       = [aws_sns_topic.gitlab_alerts.arn]

  dimensions = {
    BucketName = aws_s3_bucket.gitlab.id
  }

  tags = var.additional_tags
}

# CloudWatch Dashboard for GitLab Infrastructure
resource "aws_cloudwatch_dashboard" "gitlab_infrastructure" {
  dashboard_name = "${var.project_name}-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.gitlab.cluster_identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "RDS Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            for i in range(3) : [
              "AWS/ElastiCache", "CPUUtilization", "CacheClusterId", 
              "${aws_elasticache_replication_group.gitlab.replication_group_id}-${format("%03d", i + 1)}"
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "Redis CPU Utilization"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.gitlab.id, "StorageType", "StandardStorage"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "S3 Bucket Size"
          period  = 86400
        }
      }
    ]
  })

  tags = var.additional_tags
}

# CloudWatch Log Insights Queries for troubleshooting
resource "aws_cloudwatch_query_definition" "rds_slow_queries" {
  name = "${var.project_name}-rds-slow-queries"

  log_group_names = [
    aws_cloudwatch_log_group.gitlab_rds.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /duration:/
| stats count() by bin(5m)
EOF
}

resource "aws_cloudwatch_query_definition" "redis_slow_commands" {
  name = "${var.project_name}-redis-slow-commands"

  log_group_names = [
    aws_cloudwatch_log_group.gitlab_redis_slow.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /slow/
| stats count() by bin(5m)
EOF
}