# Real-apply end-to-end fixture for the AWS primitives.
#
# Composes low-cost modules exactly as the security/network stages do:
#   data/kms-key -> data/log-archive-bucket (SSE-KMS + Object Lock)
#   network/vpc (1 AZ, 1 private tier, no NAT, no IGW, S3 gateway endpoint)
# writes one canary object through the bucket's DEFAULT encryption and
# retention, then READS THE RESULT BACK from the real APIs so the assertions in
# e2e.tftest.hcl check what AWS actually stored rather than echoing inputs.
# `terraform test` destroys everything at the end of the run.
#
# Every name carries "e2e-<run_id>-<attempt>". Cost: well under $1 per run
# (see docs/guides/sandbox-e2e.md).

data "aws_caller_identity" "current" {}

# The CI session is an assumed-role ARN; the key policy needs the IAM role ARN.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name       = "e2e-${var.run_id}-${var.run_attempt}"
  account_id = data.aws_caller_identity.current.account_id
  runner_arn = data.aws_iam_session_context.current.issuer_arn

  archive_bucket_name = "${local.name}-archive-${local.account_id}"
  sink_bucket_name    = "${local.name}-sink-${local.account_id}"
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

module "kms" {
  source = "../../../modules/aws/data/kms-key"

  alias                   = "${local.name}-archive"
  deletion_window_in_days = 7
  org_id                  = var.org_id
  management_account_id   = local.account_id

  # The runner role administers the key (so teardown can schedule deletion)
  # and may use it only through S3 (so the canary object can be written).
  key_admin_arn = local.runner_arn
  key_user_arns = [local.runner_arn]
  via_services  = ["s3.${var.region}.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# Sink bucket: receives the archive bucket's S3 access logs and the VPC flow
# logs. Kept OUT of the Object Lock bucket so nothing written by AWS services
# can block teardown. force_destroy empties it on destroy.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "sink" {
  bucket        = local.sink_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "sink" {
  bucket = aws_s3_bucket.sink.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sink" {
  bucket = aws_s3_bucket.sink.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 server access logging cannot deliver to an SSE-KMS bucket, so the sink uses
# SSE-S3 (AWS documents this exception for access-log destinations).
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "sink" {
  bucket = aws_s3_bucket.sink.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "sink" {
  bucket = aws_s3_bucket.sink.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogs"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.sink.arn}/*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "VpcFlowLogsWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.sink.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "VpcFlowLogsAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.sink.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.sink.arn, "${aws_s3_bucket.sink.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.sink]
}

# ---------------------------------------------------------------------------
# Log-archive bucket (SSE-KMS + Object Lock). GOVERNANCE mode with a 1-day
# retention so the canary version can be removed with
# s3:BypassGovernanceRetention at teardown; COMPLIANCE would make the bucket
# undeletable for the retention period.
# ---------------------------------------------------------------------------

module "archive" {
  source = "../../../modules/aws/data/log-archive-bucket"

  log_archive_bucket_name = local.archive_bucket_name
  kms_key_arn             = module.kms.key_arn
  org_id                  = var.org_id
  object_lock_mode        = "GOVERNANCE"
  retention_days          = 1
  access_log_bucket       = aws_s3_bucket.sink.id
  access_log_prefix       = "archive-access/"

  depends_on = [aws_s3_bucket_policy.sink]
}

# Bucket-level configuration (default encryption, Object Lock default retention)
# is eventually consistent; give it a moment before the first object write.
resource "terraform_data" "archive_settle" {
  triggers_replace = [module.archive.bucket_arn]

  provisioner "local-exec" {
    command = "sleep 20"
  }

  depends_on = [module.archive]
}

# Canary object written WITHOUT any encryption or lock arguments: the read-back
# below proves the bucket's defaults (CMK + GOVERNANCE retention) were applied.
resource "aws_s3_object" "canary" {
  bucket             = module.archive.bucket_id
  key                = "e2e/canary.txt"
  content            = "e2e canary ${local.name}"
  content_type       = "text/plain"
  checksum_algorithm = "SHA256"

  # Deletes every version and bypasses GOVERNANCE retention on destroy.
  force_destroy = true

  depends_on = [terraform_data.archive_settle]
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "vpc" {
  source = "../../../modules/aws/network/vpc"

  name               = local.name
  cidr_block         = "10.250.0.0/16"
  region             = var.region
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 1)
  az_count           = 1

  subnets = {
    private = { newbits = 8, number_offset = 0 }
  }

  flow_log_destination_arn = aws_s3_bucket.sink.arn
  gateway_endpoints        = ["s3"]

  depends_on = [aws_s3_bucket_policy.sink]
}

# ---------------------------------------------------------------------------
# Read-back from the real APIs. depends_on defers each read until after the
# resources have been applied.
# ---------------------------------------------------------------------------

data "aws_s3_object" "canary" {
  bucket = module.archive.bucket_id
  key    = aws_s3_object.canary.key

  depends_on = [aws_s3_object.canary]
}

data "aws_kms_key" "archive" {
  key_id = module.kms.key_arn

  depends_on = [module.kms]
}

data "aws_vpc" "this" {
  id = module.vpc.vpc_id

  depends_on = [module.vpc]
}

data "aws_subnet" "private" {
  id = module.vpc.subnet_ids_by_tier["private"][0]

  depends_on = [module.vpc]
}

data "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"

  depends_on = [module.vpc]
}
