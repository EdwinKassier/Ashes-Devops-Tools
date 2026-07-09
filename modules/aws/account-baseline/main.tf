# Per-account security defaults that the declarative EC2 organization policy
# does NOT cover.
#
# The declarative EC2 policy governs EC2-service defaults centrally; the
# controls here are account/Region-scoped settings that live outside it:
#
#   - default EBS encryption (per enabled Region, optionally with a CMK)
#   - the account-level S3 Block Public Access
#   - the IAM account password policy
#
# Default-VPC deletion is deliberately NOT managed here: it is handled by the
# out-of-band StackSet (Convention 9), because deleting the default VPC is a
# one-shot bootstrap action rather than a continuously-reconciled setting.
#
# EBS encryption-by-default and the default KMS key are per-Region settings, so
# they fan out over var.aws_enabled_regions using the provider's region
# argument (v6 multi-Region support) rather than provider aliases.

resource "aws_ebs_encryption_by_default" "this" {
  for_each = toset(var.aws_enabled_regions)
  region   = each.value
  enabled  = true
}

resource "aws_ebs_default_kms_key" "this" {
  for_each = var.kms_key_arn != "" ? toset(var.aws_enabled_regions) : toset([])
  region   = each.value
  key_arn  = var.kms_key_arn
}

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = var.password_min_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = var.password_max_age
  password_reuse_prevention      = var.password_reuse_prevention
}
