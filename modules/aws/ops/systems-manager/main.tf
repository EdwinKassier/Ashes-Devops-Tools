# AWS Systems Manager operational baseline for the SRA landing zone.
#
# Provides three org-wide SSM capabilities intended to be delegated to (or run
# per-account via) the workload stage:
#   1. A Session Manager preferences document that forces KMS-encrypted sessions
#      and dual logging to S3 and CloudWatch Logs (no plaintext shell access).
#   2. One patch baseline per operating system (each set as the account default
#      for its OS) that auto-approves security updates of Critical/Important
#      severity (and Bugfix on Linux) after a delay.
#   3. Two AWS-RunPatchBaseline associations: a daily Scan on every managed
#      instance (compliance reporting) and a weekly Install (RebootIfNeeded,
#      10% concurrency) that runs only at its cron time, never at apply time.
#   4. A software-inventory association that gathers inventory from all managed
#      instances on a schedule using the AWS-managed GatherSoftwareInventory doc.
#
# A State Manager association on a cron schedule is the AWS-documented way to
# patch without a maintenance window, so the module creates no window.
#
# Per-account association: this module is instantiated per account via the
# workload stage (Convention 9 — home account via the stage, workload accounts
# via aws-workload). The Session Manager "Quick Setup" patch policies remain
# partly console-driven; this module manages the baselines, defaults and
# associations, not the Quick Setup CloudFormation StackSets.

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

  tags = var.tags
}

locals {
  # Effective OS set: the deprecated single-OS input wins when set.
  patch_operating_systems = var.patch_operating_system != null ? toset([var.patch_operating_system]) : var.patch_operating_systems

  # Approval-rule filters per OS family, matching the keys each OS supports
  # (Windows has MSRC_SEVERITY and its own classification names). Same
  # approval scope as the AWS predefined baselines.
  linux_patch_filters = {
    CLASSIFICATION = ["Security", "Bugfix"]
    SEVERITY       = ["Critical", "Important"]
  }
  windows_patch_filters = {
    CLASSIFICATION = ["CriticalUpdates", "SecurityUpdates"]
    MSRC_SEVERITY  = ["Critical", "Important"]
  }

  # Install targets: every managed instance, or only those with the opt-in tag.
  patch_install_target = var.patch_install_target_tag == null ? {
    key    = "InstanceIds"
    values = ["*"]
    } : {
    key    = "tag:${var.patch_install_target_tag.key}"
    values = [var.patch_install_target_tag.value]
  }
}

# Patch baselines: auto-approve security updates (Critical/Important) after a delay.
resource "aws_ssm_patch_baseline" "this" {
  for_each = local.patch_operating_systems

  # The AMAZON_LINUX_2 baseline keeps the pre-multi-OS name so the moved block
  # below re-addresses it in place instead of replacing it.
  name             = each.key == "AMAZON_LINUX_2" ? var.patch_baseline_name : "${var.patch_baseline_name}-${lower(replace(each.key, "_", "-"))}"
  operating_system = each.key

  approval_rule {
    approve_after_days = var.patch_approve_after_days

    patch_filter {
      key    = "PRODUCT"
      values = ["*"]
    }

    dynamic "patch_filter" {
      for_each = each.key == "WINDOWS" ? local.windows_patch_filters : local.linux_patch_filters
      content {
        key    = patch_filter.key
        values = patch_filter.value
      }
    }
  }

  tags = var.tags
}

# Make each baseline the account default for its operating system.
resource "aws_ssm_default_patch_baseline" "this" {
  for_each = aws_ssm_patch_baseline.this

  baseline_id      = each.value.id
  operating_system = each.value.operating_system
}

# Single-baseline state (before patch_operating_systems) was always Amazon Linux 2.
moved {
  from = aws_ssm_patch_baseline.this
  to   = aws_ssm_patch_baseline.this["AMAZON_LINUX_2"]
}

moved {
  from = aws_ssm_default_patch_baseline.this
  to   = aws_ssm_default_patch_baseline.this["AMAZON_LINUX_2"]
}

# Daily patch compliance scan on every managed instance (no install, no reboot).
resource "aws_ssm_association" "patch_scan" {
  name                = "AWS-RunPatchBaseline"
  association_name    = "${var.patch_baseline_name}-scan"
  schedule_expression = "rate(1 day)"
  compliance_severity = "HIGH"
  max_concurrency     = "10%"
  max_errors          = "10%"

  parameters = {
    Operation = "Scan"
  }

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  tags = var.tags
}

# Weekly patch install. apply_only_at_cron_interval: the first run is the next
# cron time, not the moment Terraform creates the association, so an apply
# never reboots instances.
resource "aws_ssm_association" "patch_install" {
  count = var.enable_patch_install ? 1 : 0

  name                        = "AWS-RunPatchBaseline"
  association_name            = "${var.patch_baseline_name}-install"
  schedule_expression         = var.patch_install_schedule
  apply_only_at_cron_interval = true
  compliance_severity         = "CRITICAL"
  max_concurrency             = "10%"
  max_errors                  = "10%"

  parameters = {
    Operation    = "Install"
    RebootOption = var.patch_reboot_option
  }

  targets {
    key    = local.patch_install_target.key
    values = local.patch_install_target.values
  }

  tags = var.tags
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
  tags                = var.tags
}
