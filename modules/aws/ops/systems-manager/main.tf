# AWS Systems Manager operational baseline for the SRA landing zone.
#
# Provides three org-wide SSM capabilities intended to be delegated to (or run
# per-account via) the workload stage:
#   1. A Session Manager preferences document that forces KMS-encrypted sessions
#      and dual logging to S3 and CloudWatch Logs (no plaintext shell access).
#   2. A patch baseline (set as the account/OS default) that auto-approves
#      Security and Bugfix updates of Critical/Important severity after a delay.
#   3. A software-inventory association that gathers inventory from all managed
#      instances on a schedule using the AWS-managed GatherSoftwareInventory doc.
#
# Per-account association: this module is instantiated per account via the
# workload stage (Convention 9 — home account via the stage, workload accounts
# via aws-workload). The Session Manager "Quick Setup" patch policies remain
# partly console-driven; this module only manages the baseline + default, not
# the Quick Setup CloudFormation StackSets.

# Session Manager preferences: KMS-encrypted, dual S3 + CloudWatch logging.
resource "aws_ssm_document" "session_preferences" {
  name            = var.session_document_name
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: KMS + S3/CloudWatch logging"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = var.log_bucket_name
      cloudWatchLogGroupName      = var.cloudwatch_log_group
      kmsKeyId                    = var.kms_key_id
      cloudWatchEncryptionEnabled = true
      s3EncryptionEnabled         = true
    }
  })
}

# Patch baseline: auto-approve Security/Bugfix, Critical/Important after delay.
resource "aws_ssm_patch_baseline" "this" {
  name             = var.patch_baseline_name
  operating_system = var.patch_operating_system

  approval_rule {
    approve_after_days = var.patch_approve_after_days

    patch_filter {
      key    = "PRODUCT"
      values = ["*"]
    }
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }
}

# Make the baseline the account default for its operating system.
resource "aws_ssm_default_patch_baseline" "this" {
  baseline_id      = aws_ssm_patch_baseline.this.id
  operating_system = aws_ssm_patch_baseline.this.operating_system
}

# Software-inventory collection across all managed instances.
resource "aws_ssm_association" "inventory" {
  name             = "AWS-GatherSoftwareInventory"
  association_name = var.inventory_association_name

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  schedule_expression = var.inventory_schedule
}
