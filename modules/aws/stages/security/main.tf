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

# Boundary propagation (tfc-oidc-baseline): the security-tooling tfc-apply role
# may only create roles that carry its own permissions boundary, so every role
# this stage creates there gets it. Derived from the security_tooling provider.
data "aws_caller_identity" "security_tooling" {
  count    = var.tfc_apply_boundary_policy_name != null ? 1 : 0
  provider = aws.security_tooling
}

data "aws_partition" "security_tooling" {
  count    = var.tfc_apply_boundary_policy_name != null ? 1 : 0
  provider = aws.security_tooling
}

locals {
  # Real AWS always returns a 12-digit account and an aws* partition; under
  # mock_provider these data sources return random strings the provider's ARN
  # validator rejects, so a malformed identity yields no boundary rather than
  # failing every mocked plan downstream (tests override the data sources).
  boundary_partition = try(data.aws_partition.security_tooling[0].partition, null)
  # ARN partition for the key-admin principals: the security-tooling
  # provider's partition when it is read, else var.partition.
  partition        = can(regex("^aws(-[a-z]+)*$", local.boundary_partition)) ? local.boundary_partition : var.partition
  boundary_account = try(data.aws_caller_identity.security_tooling[0].account_id, null)
  security_tooling_boundary_arn = (
    var.tfc_apply_boundary_policy_name != null && can(regex("^aws(-[a-z]+)*$", local.boundary_partition)) && can(regex("^[0-9]{12}$", local.boundary_account))
    ? "arn:${local.boundary_partition}:iam::${local.boundary_account}:policy/${var.tfc_apply_boundary_policy_name}"
    : null
  )

  # The ARN the assumption alarm watches: the role this stage creates when
  # create_break_glass is true, otherwise the externally-managed ARN the caller
  # passes. So "managed here" and "monitored here" stay in lockstep.
  effective_break_glass_role_arn = var.aws.create_break_glass ? module.break_glass[0].break_glass_role_arn : var.aws.break_glass_role_arn

  # Key administrator per CMK: the explicit key_admin_arn, else the key's own
  # account role key_admin_role_name (tfc-apply by default — the principal that
  # applies the key, so the key can never be created un-administrable).
  key_admin_arns = {
    log_archive      = coalesce(var.aws.key_admin_arn, "arn:${local.partition}:iam::${var.log_archive_account_id}:role/${var.aws.key_admin_role_name}")
    forensics        = coalesce(var.aws.key_admin_arn, "arn:${local.partition}:iam::${var.forensics_account_id}:role/${var.aws.key_admin_role_name}")
    security_tooling = coalesce(var.aws.key_admin_arn, "arn:${local.partition}:iam::${var.security_tooling_account_id}:role/${var.aws.key_admin_role_name}")
  }

  # kms:PutKeyPolicy holder per CMK: the member-account break-glass role in the
  # key's OWN account (deployed to every member account by the aws-organization
  # member break-glass StackSet), so the pipeline (key admin) cannot rewrite the
  # key policy and grant itself kms:Decrypt — at the key-policy level as well as
  # via the deny-tamper SCP. PutKeyPolicy is not a cross-account operation, so
  # the management-account break-glass role cannot be used here. Null role name
  # = legacy (key admin also holds PutKeyPolicy).
  key_account_ids = {
    log_archive      = var.log_archive_account_id
    forensics        = var.forensics_account_id
    security_tooling = var.security_tooling_account_id
  }
  key_policy_admin_arns = {
    for k, acct in local.key_account_ids : k => (
      var.key_policy_admin_role_name == null ? [] : ["arn:${local.partition}:iam::${acct}:role/${var.key_policy_admin_role_name}"]
    )
  }
}

# ---------------------------------------------------------------------------
# Managed break-glass role (management account)
#
# Opt-in. Deny-all by default; AdministratorAccess only while break_glass_active.
# MFA-required trust scoped to break_glass_trusted_principals. Its assumption is
# alarmed by the security_notifications module below via the effective ARN.
# ---------------------------------------------------------------------------

module "break_glass" {
  source = "../../iam/iam-role"
  count  = var.aws.create_break_glass ? 1 : 0
  providers = {
    aws = aws.management
  }

  roles                          = {}
  enable_break_glass             = true
  break_glass_role_name          = var.aws.break_glass_role_name
  break_glass_trusted_principals = var.aws.break_glass_trusted_principals
  break_glass_mfa_max_age        = var.aws.break_glass_mfa_max_age
  break_glass_active             = var.aws.break_glass_active
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
  key_policy_admin_arns = local.key_policy_admin_arns["log_archive"]
  key_user_arns         = try(var.aws.kms_key_user_arns["log_archive"], [])
  enable_protection_tag = var.aws.enable_kms_protection_tag
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
  key_policy_admin_arns = local.key_policy_admin_arns["forensics"]
  key_user_arns         = try(var.aws.kms_key_user_arns["forensics"], [])
  enable_protection_tag = var.aws.enable_kms_protection_tag
}

# Security-tooling CMK. The log CMK lives in the log-archive account and its key
# policy grants only log-delivery service principals + the key admin, so an SNS
# topic or SSM session in the security-tooling account cannot use it (it would
# get KMSAccessDenied). This key lives IN the security-tooling account and grants
# the local detective/session services (SNS, SSM, CloudWatch) usage, scoped to
# this account (aws:SourceAccount). It carries no log-delivery grants.
module "sectool_cmk" {
  source = "../../data/kms-key"
  providers = {
    aws = aws.security_tooling
  }

  alias                  = "security-tooling"
  org_id                 = var.org_id
  management_account_id  = var.management_account_id
  key_admin_arn          = local.key_admin_arns["security_tooling"]
  key_policy_admin_arns  = local.key_policy_admin_arns["security_tooling"]
  key_user_arns          = try(var.aws.kms_key_user_arns["security_tooling"], [])
  enable_protection_tag  = var.aws.enable_kms_protection_tag
  log_service_principals = []
  service_principals     = local.sectool_cmk_service_principals
  # Local services only: scope the grant to this account (aws:SourceAccount),
  # not the whole org.
  service_principal_scope = "account"
  key_account_id          = var.security_tooling_account_id
}

# ---------------------------------------------------------------------------
# Central log-archive bucket (log-archive account)
# ---------------------------------------------------------------------------

module "log_archive_bucket" {
  source = "../../data/log-archive-bucket"
  providers = {
    aws = aws.log_archive
  }

  log_archive_bucket_name = var.aws.log_archive_bucket_name
  kms_key_arn             = module.log_cmk.key_arn
  org_id                  = var.org_id
}

# ---------------------------------------------------------------------------
# Organization CloudTrail (management account)
#
# Legacy path, and the trail every existing estate runs. With
# enable_cloudtrail_delegated_admin it stays in configuration (so Terraform
# never destroys it; the management role cannot delete it either) until the
# migration runbook retires it with break-glass and sets
# create_management_trail = false.
# ---------------------------------------------------------------------------

locals {
  create_management_trail        = var.aws.create_organization_trail && (!var.aws.enable_cloudtrail_delegated_admin || var.aws.create_management_trail)
  create_delegated_admin_trail   = var.aws.create_organization_trail && var.aws.enable_cloudtrail_delegated_admin
  delegated_admin_log_group_name = try(module.cloudtrail_delegated_admin[0].cloudwatch_log_group_name, null)
}

module "cloudtrail" {
  source = "../../security/cloudtrail-org"
  # false when another owner (e.g. AWS Control Tower) already runs the org trail.
  count = local.create_management_trail ? 1 : 0
  providers = {
    aws = aws.management
  }

  log_archive_bucket = module.log_archive_bucket.bucket_name
  kms_key_arn        = module.log_cmk.key_arn

  # CIS AWS 3.8/3.9: S3 object-level data events (WriteOnly by default; the
  # log-archive bucket is excluded inside the module to avoid recursion).
  cloudtrail_s3_data_events           = var.aws.cloudtrail_s3_data_events
  s3_data_events_excluded_bucket_arns = var.aws.cloudtrail_s3_data_events_excluded_bucket_arns
  enable_lambda_data_events           = var.aws.cloudtrail_lambda_data_events

  # CIS AWS section 4: CloudWatch Logs + metric-filter alarms (default ON). The
  # module creates its own logs-granted CMK and KMS-encrypted SNS topic in the
  # management account unless existing ones are supplied.
  enable_cloudwatch_logs         = var.aws.enable_cloudwatch_logs
  cloudwatch_logs_role_arn       = var.aws.cloudtrail_cloudwatch_role_arn
  cloudwatch_logs_retention_days = var.aws.cloudwatch_logs_retention_days
  cloudwatch_logs_kms_key_arn    = var.aws.cloudwatch_logs_kms_key_arn
  # The management-account aws-security apply role manages the CMK by key
  # policy (its own IAM policy grants no tag-based kms:*).
  cloudwatch_logs_kms_key_manager_arns = coalesce(var.cloudwatch_logs_kms_key_manager_arns, ["arn:${var.partition}:iam::${var.management_account_id}:role/${var.management_role_name_prefix}aws-security-apply"])
  alarm_sns_topic_arn                  = var.aws.cloudtrail_alarm_sns_topic_arn
  alarm_subscriptions                  = coalesce(var.aws.cloudtrail_alarm_subscribers, var.aws.notification_subscribers)
  cis_alarms_excluded                  = var.aws.cloudtrail_cis_alarms_excluded

  depends_on = [module.log_archive_bucket]
}

# ---------------------------------------------------------------------------
# Organization CloudTrail managed by the CloudTrail delegated administrator
# (security tooling; opt-in, enable_cloudtrail_delegated_admin)
#
# aws-organization registers security tooling as the CloudTrail delegated admin.
# The trail is created with the security-tooling provider: the management
# account still owns it (its ARN, aws:SourceAccount and the KMS encryption
# context carry the management account ID, which the log CMK and log-archive
# bucket policies already allow), but every change to it now comes from a
# member account, so the deny-tamper SCP constrains it. CloudTrail requires the
# CloudWatch Logs group and its role to exist in the calling account, so the
# module creates them here, with their own CMK, topic and CIS alarms. A
# different trail name keeps both trails logging until the old one is retired.
# ---------------------------------------------------------------------------

module "cloudtrail_delegated_admin" {
  source = "../../security/cloudtrail-org"
  count  = local.create_delegated_admin_trail ? 1 : 0
  providers = {
    aws = aws.security_tooling
  }

  trail_name             = var.aws.cloudtrail_delegated_admin_trail_name
  trail_owner_account_id = var.management_account_id
  log_archive_bucket     = module.log_archive_bucket.bucket_name
  kms_key_arn            = module.log_cmk.key_arn

  cloudtrail_s3_data_events           = var.aws.cloudtrail_s3_data_events
  s3_data_events_excluded_bucket_arns = var.aws.cloudtrail_s3_data_events_excluded_bucket_arns
  enable_lambda_data_events           = var.aws.cloudtrail_lambda_data_events

  # Everything CloudWatch-side is created in security tooling: the
  # management-account overrides (cloudtrail_cloudwatch_role_arn,
  # cloudwatch_logs_kms_key_arn, cloudtrail_alarm_sns_topic_arn) do not apply.
  # The delivery role carries the tfc-apply permissions boundary; the CMK is
  # administered by the account root (so by IAM in that account).
  enable_cloudwatch_logs                        = var.aws.enable_cloudwatch_logs
  cloudwatch_logs_retention_days                = var.aws.cloudwatch_logs_retention_days
  cloudwatch_logs_role_permissions_boundary_arn = local.security_tooling_boundary_arn
  cloudwatch_logs_kms_key_manager_arns          = []
  alarm_subscriptions                           = coalesce(var.aws.cloudtrail_alarm_subscribers, var.aws.notification_subscribers)
  cis_alarms_excluded                           = var.aws.cloudtrail_cis_alarms_excluded

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

  aws_enabled_regions = var.aws.aws_enabled_regions
  # Null role ARNs -> the module creates the AWSServiceRoleForConfig SLR and
  # the org aggregator role in the security-tooling account.
  config_role_arn            = var.aws.config_role_arn
  create_service_linked_role = var.aws.create_config_service_linked_role
  account_id                 = var.security_tooling_account_id
  aggregator_role_arn        = var.aws.aggregator_role_arn
  log_archive_bucket         = module.log_archive_bucket.bucket_name
  recorder_only              = false
  # Record global resource types in the home Region only, not once per Region.
  home_region = var.aws_region
  # Record ALL supported resource types (default true, the full-coverage but
  # most expensive Config mode). Set false for cost-sensitive non-prod.
  record_all_supported = var.aws.config_record_all_supported
  # The org aggregator role is created in the security-tooling account.
  permissions_boundary_arn = local.security_tooling_boundary_arn
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

  aws_enabled_regions         = var.aws.aws_enabled_regions
  security_tooling_account_id = var.security_tooling_account_id
  # Agentless EBS malware scanning (default true, billed per GB scanned). Set
  # false for non-prod where it is not required.
  enable_ebs_malware_protection = var.aws.guardduty_enable_ebs_malware_protection
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

  # Home region (the provider's) plus every enabled region, via the resource-level
  # region argument.
  home_region                     = var.aws_region
  regions                         = distinct(concat([var.aws_region], var.aws.aws_enabled_regions))
  enable_internal_access_analyzer = var.aws.enable_internal_access_analyzer
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
  backup_account_id           = var.backup_account_id
  # IAM Identity Center delegated admin should live in a dedicated
  # identity account, not shared-services (delegated admin can assign access into the
  # management account — keep its blast radius tight). Default null keeps the previous
  # shared-services target (unchanged); set identity_account_id to a dedicated account.
  # PREVIEW: opt-in (default off), not yet validated against a real apply. before relying on the new target.
  identity_account_id = coalesce(var.aws.identity_account_id, var.shared_services_account_id)

  # aws-organization registers the CloudTrail delegated admin through CloudTrail
  # once the trail moves to security tooling.
  register_cloudtrail_admin = !var.aws.enable_cloudtrail_delegated_admin
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

  enabled_services            = var.aws.enabled_security_services
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

  enable_security_lake        = var.aws.enable_security_lake
  meta_store_manager_role_arn = local.meta_store_manager_role_arn
  kms_key_id                  = module.log_cmk.key_arn
  aws_enabled_regions         = var.aws.aws_enabled_regions
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

  enable_incident_response = var.aws.enable_incident_response
  forensics_account_id     = var.forensics_account_id
  org_id                   = var.org_id
  # Let the forensics role decrypt snapshots encrypted with the forensics CMK.
  forensics_kms_key_arn = module.forensics_cmk.key_arn
  quarantine_vpc_id     = var.quarantine_vpc_id
  # Both IR roles are created in the security-tooling account.
  permissions_boundary_arn = local.security_tooling_boundary_arn
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
  kms_key_id               = module.sectool_cmk.key_arn
  notification_subscribers = var.aws.notification_subscribers
  break_glass_role_arn     = local.effective_break_glass_role_arn
  # The delegated-admin trail's log group lives in this (security-tooling)
  # account, so the break-glass metric alarm can read it by default.
  cloudtrail_log_group_name = var.cloudtrail_log_group_name != "" ? var.cloudtrail_log_group_name : (local.delegated_admin_log_group_name == null ? "" : local.delegated_admin_log_group_name)
}

# ---------------------------------------------------------------------------
# Service-quota management (security tooling)
# ---------------------------------------------------------------------------

module "service_quotas" {
  source = "../../governance/service-quotas"
  providers = {
    aws = aws.security_tooling
  }

  enable_service_quotas   = var.aws.enable_service_quotas
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
