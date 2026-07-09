# aws-security stage (phase-2)
#
# Thin orchestration wrapper composing the SRA security baseline across four
# accounts via aliased providers:
#   - aws.management       — org management (payer) account
#   - aws.security_tooling — the delegated-administrator / security tooling account
#   - aws.log_archive      — the central log-archive account
#   - aws.forensics        — the forensics account
#
# Data flows between children: the log CMK encrypts the log-archive bucket,
# CloudTrail and the org services; the log-archive bucket name feeds CloudTrail,
# Config and Systems Manager; the security-notifications topic feeds the
# service-quota usage alarms.
#
# Convention 9: this stage deploys the Config recorder + org aggregator from the
# Security Tooling account only (recorder_only = false). Recorders for the other
# member accounts come from their own layers / the out-of-band StackSet.
#
# NOTE: firewall-manager-org is intentionally NOT composed here. FMS admin
# registration is an explicit, one-time decision that can live in this stage or
# in the network stage; it is left out of the default security stage so the
# choice of FMS administrator is made deliberately. See README.

# ---------------------------------------------------------------------------
# KMS customer-managed keys (log-archive account + forensics account)
# ---------------------------------------------------------------------------

module "log_cmk" {
  source = "../../aws/kms-key"
  providers = {
    aws = aws.log_archive
  }

  alias                 = "log-archive"
  org_id                = var.org_id
  management_account_id = var.management_account_id
  key_admin_arn         = var.key_admin_arn
  # log_service_principals uses the module SRA default
  # (cloudtrail / config / securitylake).
}

module "forensics_cmk" {
  source = "../../aws/kms-key"
  providers = {
    aws = aws.forensics
  }

  alias                 = "forensics"
  org_id                = var.org_id
  management_account_id = var.management_account_id
  key_admin_arn         = var.key_admin_arn
}

# ---------------------------------------------------------------------------
# Central log-archive bucket (log-archive account)
# ---------------------------------------------------------------------------

module "log_archive_bucket" {
  source = "../../aws/log-archive-bucket"
  providers = {
    aws = aws.log_archive
  }

  log_archive_bucket_name = var.log_archive_bucket_name
  kms_key_arn             = module.log_cmk.key_arn
  org_id                  = var.org_id
}

# ---------------------------------------------------------------------------
# Organization CloudTrail (management account)
# ---------------------------------------------------------------------------

module "cloudtrail" {
  source = "../../aws/cloudtrail-org"
  providers = {
    aws = aws.management
  }

  log_archive_bucket = module.log_archive_bucket.bucket_name
  kms_key_arn        = module.log_cmk.key_arn

  depends_on = [module.log_archive_bucket]
}

# ---------------------------------------------------------------------------
# AWS Config: recorder + delivery channel + org aggregator (security tooling)
# ---------------------------------------------------------------------------

module "config" {
  source = "../../aws/config-org"
  providers = {
    aws = aws.security_tooling
  }

  aws_enabled_regions = var.aws_enabled_regions
  config_role_arn     = var.config_role_arn
  aggregator_role_arn = var.aggregator_role_arn
  log_archive_bucket  = module.log_archive_bucket.bucket_name
  recorder_only       = false
}

# ---------------------------------------------------------------------------
# GuardDuty org-wide (delegated admin = security tooling; registered from mgmt)
# ---------------------------------------------------------------------------

module "guardduty" {
  source = "../../aws/guardduty-org"
  providers = {
    aws            = aws.security_tooling
    aws.management = aws.management
  }

  aws_enabled_regions         = var.aws_enabled_regions
  security_tooling_account_id = var.security_tooling_account_id
}

# ---------------------------------------------------------------------------
# Security Hub CENTRAL configuration (delegated admin = security tooling)
# ---------------------------------------------------------------------------

module "securityhub" {
  source = "../../aws/securityhub-org"
  providers = {
    aws            = aws.security_tooling
    aws.management = aws.management
  }

  security_tooling_account_id = var.security_tooling_account_id
  org_root_id                 = var.org_root_id
  home_region                 = var.aws_region
}

# ---------------------------------------------------------------------------
# IAM Access Analyzer org analyzers (security tooling)
# ---------------------------------------------------------------------------

module "access_analyzer" {
  source = "../../aws/access-analyzer-org"
  providers = {
    aws = aws.security_tooling
  }
}

# ---------------------------------------------------------------------------
# Delegated-administrator registrations (from the management account)
# ---------------------------------------------------------------------------

module "delegated_admin" {
  source = "../../aws/security-delegated-admin"
  providers = {
    aws = aws.management
  }

  security_tooling_account_id = var.security_tooling_account_id
  identity_account_id         = var.shared_services_account_id
}

# ---------------------------------------------------------------------------
# Org-security services: Macie / Inspector / Detective / Resource Explorer
# ---------------------------------------------------------------------------

module "org_security_service" {
  source = "../../aws/org-security-service"
  providers = {
    aws            = aws.security_tooling
    aws.management = aws.management
  }

  enabled_services            = var.enabled_security_services
  security_tooling_account_id = var.security_tooling_account_id
}

# ---------------------------------------------------------------------------
# Amazon Security Lake (security tooling)
# ---------------------------------------------------------------------------

module "securitylake" {
  source = "../../aws/securitylake"
  providers = {
    aws = aws.security_tooling
  }

  enable_security_lake        = var.enable_security_lake
  meta_store_manager_role_arn = var.meta_store_manager_role_arn
  kms_key_id                  = module.log_cmk.key_arn
  aws_enabled_regions         = var.aws_enabled_regions
}

# ---------------------------------------------------------------------------
# Systems Manager baseline (security tooling)
# ---------------------------------------------------------------------------

module "systems_manager" {
  source = "../../aws/systems-manager"
  providers = {
    aws = aws.security_tooling
  }

  log_bucket_name = module.log_archive_bucket.bucket_name
  kms_key_id      = module.log_cmk.key_arn
}

# ---------------------------------------------------------------------------
# Incident-response automation (security tooling)
# ---------------------------------------------------------------------------

module "incident_response" {
  source = "../../aws/incident-response"
  providers = {
    aws = aws.security_tooling
  }

  enable_incident_response = var.enable_incident_response
  forensics_account_id     = var.forensics_account_id
  org_id                   = var.org_id
}

# ---------------------------------------------------------------------------
# Security notifications detective control (security tooling)
# ---------------------------------------------------------------------------

module "security_notifications" {
  source = "../../aws/security-notifications"
  providers = {
    aws = aws.security_tooling
  }

  kms_key_id               = module.log_cmk.key_arn
  notification_subscribers = var.notification_subscribers
  break_glass_role_arn     = var.break_glass_role_arn
}

# ---------------------------------------------------------------------------
# Service-quota management (security tooling)
# ---------------------------------------------------------------------------

module "service_quotas" {
  source = "../../aws/service-quotas"
  providers = {
    aws = aws.security_tooling
  }

  enable_service_quotas   = var.enable_service_quotas
  notifications_topic_arn = module.security_notifications.topic_arn
}
