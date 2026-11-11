# Managed PostgreSQL on Aurora for the landing zone.
#
# Composes an aws_rds_cluster (engine aurora-postgresql) with one or more
# aws_rds_cluster_instances, a private DB subnet group, and a Terraform-side
# deletion guard.
#
# Secure-by-default:
#   - storage_encrypted = true with a REQUIRED customer-managed KMS key (no
#     default AWS key)
#   - cluster lives in PRIVATE subnets; instances are never publicly_accessible
#   - deletion_protection defaults on, plus a terraform_data guard that blocks an
#     accidental `terraform destroy` or replacement of the cluster
#   - automated backups retained (default 7 days), final snapshot taken on delete
#   - IAM database authentication on by default
#   - Performance Insights on, encrypted with a CMEK
#   - master password managed by RDS in Secrets Manager by default, so it never
#     lands in Terraform state
#
# Serverless v2 is opt-in (enable_serverless_v2): the cluster stays engine_mode
# "provisioned" and gains a serverlessv2_scaling_configuration, while instances
# switch to the db.serverless class.

locals {
  # Serverless v2 keeps engine_mode "provisioned" but uses the db.serverless
  # instance class and a scaling configuration block.
  instance_class = var.enable_serverless_v2 ? "db.serverless" : var.instance_class

  final_snapshot_identifier = var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : "${var.name}-final"

  performance_insights_kms_key_id = var.performance_insights_kms_key_arn != "" ? var.performance_insights_kms_key_arn : var.kms_key_id
}

# ── DB subnet group (private) ─────────────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnets"
  subnet_ids = var.subnet_ids

  tags = var.tags
}

# ── Cluster ───────────────────────────────────────────────────────────────────

resource "aws_rds_cluster" "this" {
  # checkov:skip=CKV2_AWS_27:Query logging needs a caller-owned cluster parameter group (log_statement); export via enabled_cloudwatch_logs_exports.
  # checkov:skip=CKV2_AWS_8:Backups are governed org-wide by the AWS Backup tag policy (modules/aws/backup/backup-org-policy), not a per-module plan.
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version

  database_name   = var.database_name
  master_username = var.master_username

  # Prefer the RDS-managed secret so the password never enters Terraform state.
  manage_master_user_password   = var.manage_master_user_password ? true : null
  master_user_secret_kms_key_id = var.manage_master_user_password && var.master_user_secret_kms_key_id != "" ? var.master_user_secret_kms_key_id : null
  # Write-only (Terraform >= 1.11): a caller-supplied password never lands in state.
  master_password_wo         = var.manage_master_user_password ? null : var.master_password
  master_password_wo_version = var.manage_master_user_password ? null : var.master_password_version

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  port                   = var.port

  # Encryption at rest with a required customer-managed key.
  storage_encrypted = true
  kms_key_id        = var.kms_key_id

  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : local.final_snapshot_identifier

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  apply_immediately               = var.apply_immediately

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.enable_serverless_v2 ? [1] : []
    content {
      min_capacity = var.serverless_v2_min_capacity
      max_capacity = var.serverless_v2_max_capacity
    }
  }

  tags = var.tags
}

# ── Cluster instances ─────────────────────────────────────────────────────────

resource "aws_rds_cluster_instance" "this" {
  # checkov:skip=CKV_AWS_118:Enhanced monitoring is opt-in via monitoring_interval
  # (default 0); enabling it requires a caller-supplied monitoring_role_arn, which
  # this reusable module does not create. Set both to turn it on.
  count = var.instance_count

  identifier         = "${var.name}-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = local.instance_class

  db_subnet_group_name = aws_db_subnet_group.this.name

  # Never reachable from the public internet.
  publicly_accessible = false

  # Apply minor-version security patches automatically (CKV_AWS_226).
  auto_minor_version_upgrade = true

  # Enhanced monitoring: opt-in. Needs a monitoring role the caller supplies.
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? var.monitoring_role_arn : null

  performance_insights_enabled    = true
  performance_insights_kms_key_id = local.performance_insights_kms_key_id

  tags = var.tags
}

# ── Deletion guard ────────────────────────────────────────────────────────────
#
# A terraform_data guard (not prevent_destroy on the cluster itself, which
# cannot be switched off by a variable). Present when deletion_protection is
# true:
#   - prevent_destroy aborts any plan that destroys the guard, so a
#     `terraform destroy` of the cluster fails at plan time.
#   - replace_triggered_by ties it to the cluster id, so any plan that would
#     REPLACE the cluster (a ForceNew change such as cluster_identifier,
#     kms_key_id or db_subnet_group_name) also plans to replace the guard and
#     fails the same way. In-place updates keep the id and are not blocked.
#   - setting deletion_protection = false while the guard exists is also
#     refused, because it would destroy the guard.
# To intentionally destroy or replace a protected cluster, first run:
#   terraform state rm '<module_address>.terraform_data.deletion_guard[0]'
# then set deletion_protection = false and apply.
resource "terraform_data" "deletion_guard" {
  count = var.deletion_protection ? 1 : 0

  input = aws_rds_cluster.this.cluster_identifier

  lifecycle {
    prevent_destroy      = true
    replace_triggered_by = [aws_rds_cluster.this.id]
  }
}

# The guard became conditional (count) so consumers can turn it off.
moved {
  from = terraform_data.deletion_guard
  to   = terraform_data.deletion_guard[0]
}
