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
# NOTE: firewall-manager-org IS composed here but gated OFF by default
# (enable_firewall_manager = false). Registering the FMS administrator is an
# explicit, one-time decision and the module ships a placeholder security-group
# policy, so the default plan creates no FMS resources; a deployment opts in and
# overrides the policies deliberately. See README.

locals {
  # The ARN the assumption alarm watches: the role this stage creates when
  # create_break_glass is true, otherwise the externally-managed ARN the caller
  # passes. So "managed here" and "monitored here" stay in lockstep (audit M3).
  effective_break_glass_role_arn = var.create_break_glass ? module.break_glass[0].break_glass_role_arn : var.break_glass_role_arn

  # Key administrator per CMK: the explicit key_admin_arn, else the key's own
  # account role key_admin_role_name (tfc-apply by default — the principal that
  # applies the key, so the key can never be created un-administrable).
  key_admin_arns = {
    log_archive      = coalesce(var.key_admin_arn, "arn:aws:iam::${var.log_archive_account_id}:role/${var.key_admin_role_name}")
    forensics        = coalesce(var.key_admin_arn, "arn:aws:iam::${var.forensics_account_id}:role/${var.key_admin_role_name}")
    security_tooling = coalesce(var.key_admin_arn, "arn:aws:iam::${var.security_tooling_account_id}:role/${var.key_admin_role_name}")
  }
}

# ---------------------------------------------------------------------------
# Managed break-glass role (management account) — audit M3
#
# Opt-in. Deny-all by default; AdministratorAccess only while break_glass_active.
# MFA-required trust scoped to break_glass_trusted_principals. Its assumption is
# alarmed by the security_notifications module below via the effective ARN.
# ---------------------------------------------------------------------------

module "break_glass" {
  source = "../../iam/iam-role"
  count  = var.create_break_glass ? 1 : 0
  providers = {
    aws = aws.management
  }

  roles                          = {}
  enable_break_glass             = true
  break_glass_role_name          = var.break_glass_role_name
  break_glass_trusted_principals = var.break_glass_trusted_principals
  break_glass_mfa_max_age        = var.break_glass_mfa_max_age
  break_glass_active             = var.break_glass_active
}

# ---------------------------------------------------------------------------
# KMS customer-managed keys (log-archive account + forensics account)
#
# key_admin_arn gets management actions only; usage is granted separately via
# kms_key_user_arns (separation of duties — the key admin cannot decrypt logs).
# The keys are tagged protected = "true" (enable_kms_protection_tag) so the
# org deny-tamper SCP blocks ScheduleKeyDeletion/DisableKey except via
# break-glass: the log archive cannot be crypto-shredded by a pipeline or
# member-account admin compromise.
# ---------------------------------------------------------------------------

module "log_cmk" {
  source = "../../data/kms-key"
  providers = {
    aws = aws.log_archive
  }

  alias                 = "log-archive"
  org_id                = var.org_id
  management_account_id = var.management_account_id
  key_admin_arn         = local.key_admin_arns["log_archive"]
  key_user_arns         = try(var.kms_key_user_arns["log_archive"], [])
  enable_protection_tag = var.enable_kms_protection_tag
  # log_service_principals uses the module SRA default
  # (cloudtrail / config / securitylake / delivery.logs for vended logs).
}

module "forensics_cmk" {
  source = "../../data/kms-key"
  providers = {
    aws = aws.forensics
  }

  alias                 = "forensics"
  org_id                = var.org_id
  management_account_id = var.management_account_id
  key_admin_arn         = local.key_admin_arns["forensics"]
  key_user_arns         = try(var.kms_key_user_arns["forensics"], [])
  enable_protection_tag = var.enable_kms_protection_tag
}

# Security-tooling CMK. The log CMK lives in the log-archive account and its key
# policy grants only log-delivery service principals + the key admin, so an SNS
# topic or SSM session in the security-tooling account cannot use it (it would
# get KMSAccessDenied). This key lives IN the security-tooling account and grants
# the local detective/session services (SNS, SSM, CloudWatch) usage, scoped by
# aws:SourceOrgID. It carries no log-delivery grants.
module "sectool_cmk" {
  source = "../../data/kms-key"
  providers = {
    aws = aws.security_tooling
  }

  alias                  = "security-tooling"
  org_id                 = var.org_id
  management_account_id  = var.management_account_id
  key_admin_arn          = local.key_admin_arns["security_tooling"]
  key_user_arns          = try(var.kms_key_user_arns["security_tooling"], [])
  enable_protection_tag  = var.enable_kms_protection_tag
  log_service_principals = []
  service_principals     = ["sns.amazonaws.com", "ssm.amazonaws.com", "cloudwatch.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# Central log-archive bucket (log-archive account)
# ---------------------------------------------------------------------------

module "log_archive_bucket" {
  source = "../../data/log-archive-bucket"
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
  source = "../../security/cloudtrail-org"
  providers = {
    aws = aws.management
  }

  log_archive_bucket = module.log_archive_bucket.bucket_name
  kms_key_arn        = module.log_cmk.key_arn

  # CIS AWS 3.8/3.9: S3 object-level data events (WriteOnly by default; the
  # log-archive bucket is excluded inside the module to avoid recursion).
  cloudtrail_s3_data_events           = var.cloudtrail_s3_data_events
  s3_data_events_excluded_bucket_arns = var.cloudtrail_s3_data_events_excluded_bucket_arns
  enable_lambda_data_events           = var.cloudtrail_lambda_data_events

  # CIS AWS section 4: CloudWatch Logs + metric-filter alarms (default ON). The
  # module creates its own logs-granted CMK and KMS-encrypted SNS topic in the
  # management account unless existing ones are supplied.
  enable_cloudwatch_logs         = var.enable_cloudwatch_logs
  cloudwatch_logs_retention_days = var.cloudwatch_logs_retention_days
  cloudwatch_logs_kms_key_arn    = var.cloudwatch_logs_kms_key_arn
  alarm_sns_topic_arn            = var.cloudtrail_alarm_sns_topic_arn
  alarm_subscriptions            = coalesce(var.cloudtrail_alarm_subscribers, var.notification_subscribers)
  cis_alarms_excluded            = var.cloudtrail_cis_alarms_excluded

  depends_on = [module.log_archive_bucket]
}

# ---------------------------------------------------------------------------
# AWS Config: recorder + delivery channel + org aggregator (security tooling)
# ---------------------------------------------------------------------------

module "config" {
  source = "../../security/config-org"
  providers = {
    aws = aws.security_tooling
  }

  aws_enabled_regions = var.aws_enabled_regions
  # Null role ARNs -> the module creates the AWSServiceRoleForConfig SLR and
  # the org aggregator role in the security-tooling account.
  config_role_arn            = var.config_role_arn
  create_service_linked_role = var.create_config_service_linked_role
  account_id                 = var.security_tooling_account_id
  aggregator_role_arn        = var.aggregator_role_arn
  log_archive_bucket         = module.log_archive_bucket.bucket_name
  recorder_only              = false
  # Record global resource types in the home Region only, not once per Region.
  home_region = var.aws_region
  # F5: record ALL supported resource types (default true, the full-coverage but
  # most expensive Config mode). Set false for cost-sensitive non-prod.
  record_all_supported = var.config_record_all_supported
}

# ---------------------------------------------------------------------------
# GuardDuty org-wide (delegated admin = security tooling; registered from mgmt)
# ---------------------------------------------------------------------------

module "guardduty" {
  source = "../../security/guardduty-org"
  providers = {
    aws            = aws.security_tooling
    aws.management = aws.management
  }

  aws_enabled_regions         = var.aws_enabled_regions
  security_tooling_account_id = var.security_tooling_account_id
  # F5: agentless EBS malware scanning (default true, billed per GB scanned). Set
  # false for non-prod where it is not required.
  enable_ebs_malware_protection = var.guardduty_enable_ebs_malware_protection
}

# ---------------------------------------------------------------------------
# Security Hub CENTRAL configuration (delegated admin = security tooling)
# ---------------------------------------------------------------------------

module "securityhub" {
  source = "../../security/securityhub-org"
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
  source = "../../security/access-analyzer-org"
  providers = {
    aws = aws.security_tooling
  }
}

# ---------------------------------------------------------------------------
# Delegated-administrator registrations (from the management account)
# ---------------------------------------------------------------------------

module "delegated_admin" {
  source = "../../security/security-delegated-admin"
  providers = {
    aws = aws.management
  }

  security_tooling_account_id = var.security_tooling_account_id
  # Audit finding A3: IAM Identity Center delegated admin should live in a dedicated
  # identity account, not shared-services (delegated admin can assign access into the
  # management account — keep its blast radius tight). Default null keeps the previous
  # shared-services target (unchanged); set identity_account_id to a dedicated account.
  # PREVIEW: opt-in (default off), not yet validated against a real apply. before relying on the new target.
  identity_account_id = coalesce(var.identity_account_id, var.shared_services_account_id)
}

# ---------------------------------------------------------------------------
# Org-security services: Macie / Inspector / Detective / Resource Explorer
# ---------------------------------------------------------------------------

module "org_security_service" {
  source = "../../security/org-security-service"
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
  source = "../../security/securitylake"
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
  source = "../../ops/systems-manager"
  providers = {
    aws = aws.security_tooling
  }

  log_bucket_name = module.log_archive_bucket.bucket_name
  # SSM sessions run in the security-tooling account, so they must use a key that
  # account can access — the sectool CMK, not the cross-account log CMK.
  kms_key_id = module.sectool_cmk.key_arn
}

# ---------------------------------------------------------------------------
# Incident-response automation (security tooling)
# ---------------------------------------------------------------------------

module "incident_response" {
  source = "../../security/incident-response"
  providers = {
    aws = aws.security_tooling
  }

  enable_incident_response = var.enable_incident_response
  forensics_account_id     = var.forensics_account_id
  org_id                   = var.org_id
  # Let the forensics role decrypt snapshots encrypted with the forensics CMK.
  forensics_kms_key_arn = module.forensics_cmk.key_arn
  quarantine_vpc_id     = var.quarantine_vpc_id
}

# ---------------------------------------------------------------------------
# Security notifications detective control (security tooling)
# ---------------------------------------------------------------------------

module "security_notifications" {
  source = "../../security/security-notifications"
  providers = {
    aws = aws.security_tooling
  }

  # The SNS topic is created in the security-tooling account, so it must be
  # encrypted with a key that account can access — the sectool CMK, not the
  # cross-account log CMK (which would fail with KMSAccessDenied on publish).
  kms_key_id                = module.sectool_cmk.key_arn
  notification_subscribers  = var.notification_subscribers
  break_glass_role_arn      = local.effective_break_glass_role_arn
  cloudtrail_log_group_name = var.cloudtrail_log_group_name
}

# ---------------------------------------------------------------------------
# Service-quota management (security tooling)
# ---------------------------------------------------------------------------

module "service_quotas" {
  source = "../../governance/service-quotas"
  providers = {
    aws = aws.security_tooling
  }

  enable_service_quotas   = var.enable_service_quotas
  notifications_topic_arn = module.security_notifications.topic_arn
}

# ---------------------------------------------------------------------------
# AWS Firewall Manager (admin = security tooling; registered from mgmt)
#
# Gated OFF by default: the FMS admin registration is a one-time decision and
# the module ships a placeholder security-group policy. When enabled, the
# Security Tooling account becomes the FMS administrator.
# ---------------------------------------------------------------------------

module "firewall_manager" {
  source = "../../security/firewall-manager-org"
  providers = {
    aws            = aws.security_tooling
    aws.management = aws.management
  }

  enable_firewall_manager = var.enable_firewall_manager
  fms_admin_account_id    = var.security_tooling_account_id
}
