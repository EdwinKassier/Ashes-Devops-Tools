# Hardened central log-archive S3 bucket for the SRA landing zone.
#
# This is the org-wide sink for CloudTrail, Config, and Security Lake log
# delivery. It is created with S3 Object Lock enabled (immutable after
# creation), Block Public Access on all four dimensions, versioning, SSE-KMS
# with a bucket key, a default Object Lock retention (COMPLIANCE by default),
# and a lifecycle that transitions to GLACIER and expires per retention_days.
#
# The bucket name (var.log_archive_bucket_name) is a cross-root naming contract:
# it must match the deterministic name that the B3 SCP references, so keep the
# two in sync.
#
# The bucket policy is built with jsonencode() in locals (not via
# data.aws_iam_policy_document) so its rendered JSON is real under
# mock_provider and its content is assertable in tests.

locals {
  bucket_arn = "arn:aws:s3:::${var.log_archive_bucket_name}"

  # Transition to GLACIER at 90 days, but never after objects expire (guards the
  # case where retention_days < 90, which S3 would otherwise reject).
  glacier_transition_days = min(90, var.retention_days)

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudTrail needs GetBucketAcl on the bucket before it will write.
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = local.bucket_arn
        Condition = { StringEquals = { "aws:SourceOrgID" = var.org_id } }
      },
      # CloudTrail object delivery, scoped to this org.
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.bucket_arn}/*"
        Condition = { StringEquals = { "aws:SourceOrgID" = var.org_id } }
      },
      # Config delivery, scoped to this org.
      {
        Sid       = "AWSConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:PutObject"]
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
        Condition = { StringEquals = { "aws:SourceOrgID" = var.org_id } }
      },
      # Security Lake delivery, scoped to this org.
      {
        Sid       = "AWSSecurityLakeWrite"
        Effect    = "Allow"
        Principal = { Service = "securitylake.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:PutObject"]
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
        Condition = { StringEquals = { "aws:SourceOrgID" = var.org_id } }
      },
      # Deny any non-TLS access to the bucket or its objects.
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_s3_bucket" "this" {
  bucket = var.log_archive_bucket_name

  # Object Lock must be enabled at creation; it cannot be toggled afterward.
  object_lock_enabled = true
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 server access logging. For the central log-archive bucket (the terminal
# log sink) this self-logs to a dedicated prefix by default; set
# var.access_log_bucket to ship access logs to a separate audit bucket instead.
resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket != "" ? var.access_log_bucket : aws_s3_bucket.this.id
  target_prefix = var.access_log_prefix
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = local.glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = local.bucket_policy
}
