# -----------------------------------------------------------------------------
# Organization identity
# -----------------------------------------------------------------------------

variable "org_id" {
  description = "AWS Organizations organization ID (o-xxxxxxxxxx). Scopes the CMK log-service grants and the incident-response forensics-role trust policy to this org."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be a valid AWS Organizations id of the form o-xxxxxxxxxx."
  }
}

variable "org_root_id" {
  description = "The organization root ID (r-xxxx) the Security Hub baseline configuration policy is associated with."
  type        = string

  validation {
    condition     = can(regex("^r-[0-9a-z]{4,32}$", var.org_root_id))
    error_message = "org_root_id must be an organization root ID of the form r-xxxx."
  }
}

# -----------------------------------------------------------------------------
# Account IDs (the multi-account SRA topology this stage wires providers to)
# -----------------------------------------------------------------------------

variable "management_account_id" {
  description = "12-digit account ID of the organization management (payer) account. Scopes the CloudTrail EncryptionContext condition on the log CMK."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "security_tooling_account_id" {
  description = "12-digit account ID of the Security Tooling (delegated-administrator) account. GuardDuty, Security Hub, Access Analyzer, Config, and the org-security services are administered from here."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}

# Kept intentionally for input symmetry with the other foundational account IDs
# and the cross-root contract: the log-archive account is targeted via the
# aws.log_archive aliased provider rather than by ID, so this value is not
# referenced in main.tf. Its regex validation still runs. tflint cannot see a
# provider-alias-only usage, so the unused-declaration rule is suppressed here.
# tflint-ignore: terraform_unused_declarations
variable "log_archive_account_id" {
  description = "12-digit account ID of the Log-Archive account that owns the central log-archive bucket and the log CMK. Provided for completeness; the account is targeted via the aws.log_archive aliased provider rather than by ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "log_archive_account_id must be a 12-digit AWS account ID."
  }
}

variable "shared_services_account_id" {
  description = "12-digit account ID of the Shared-Services (Identity) account nominated as the IAM Identity Center delegated administrator by the security-delegated-admin module."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be a 12-digit AWS account ID."
  }
}

variable "forensics_account_id" {
  description = "12-digit account ID of the forensics account trusted to assume the incident-response snapshot-sharing role. Also owns the forensics CMK (targeted via the aws.forensics aliased provider)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.forensics_account_id))
    error_message = "forensics_account_id must be a 12-digit AWS account ID."
  }
}

# -----------------------------------------------------------------------------
# Region topology
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "Home (aggregation) Region. Used as the Security Hub home_region for the region-scoped standard ARNs."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must be a non-empty Region name."
  }
}

variable "aws" {
  description = "The aws section of the security stage: every tuning input the aws-security root takes from config/landing-zone.yaml (aws.*) or from its aws_overrides variable, in one object. Each attribute is documented in the type; an unset (or null) attribute takes the default shown there. log_archive_bucket_name is required. The root fills notification_subscribers, the profile-driven toggles and cloudtrail_cloudwatch_role_arn from its own derivations."
  type = object({
    # Regions in which the regional security services (Config, GuardDuty, Security Lake) are enabled.
    # One set of per-Region resources is created for each entry.
    aws_enabled_regions = optional(list(string), ["eu-west-2"])
    # Deterministic name of the central log-archive bucket. Cross-root naming contract: it must match
    # the name the log-tamper SCP references.
    log_archive_bucket_name = optional(string)
    # Account-qualified ARN of the principal granted key ADMINISTRATION (management actions only: no
    # Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant) on the log-archive, forensics and
    # security-tooling CMKs. Null (default) grants each key's OWN account role key_admin_role_name
    # (the TFC OIDC baseline tfc-apply role that applies this stage), e.g. arn:aws:iam::<log-archive
    # id>:role/tfc-apply, so the keys can never be locked out of management. Grant key usage
    # separately via kms_key_user_arns.
    key_admin_arn = optional(string)
    # With key_admin_arn = null, the role name (in each CMK's own account) granted key administration.
    # Default tfc-apply: the role the TFC OIDC baseline creates and this stage applies as, so it must
    # already exist. Set to your own per-account admin role if you run with
    # OrganizationAccountAccessRole instead.
    key_admin_role_name = optional(string, "tfc-apply")
    # Principals granted key USAGE (Encrypt/Decrypt/ReEncrypt/GenerateDataKey/DescribeKey) per CMK,
    # keyed by log_archive / forensics / security_tooling. Separate from key_admin_arn (administration
    # only). Missing keys mean no general-usage grant beyond the built-in service-principal grants.
    kms_key_user_arns = optional(map(list(string)), {})
    # Tag the log-archive, forensics and security-tooling CMKs protected = "true" so the organization
    # deny-tamper SCP blocks key deletion/disablement and protection-tag removal except via break-
    # glass. Default true.
    enable_kms_protection_tag = optional(bool, true)
    # ARN of the IAM role AWS Config assumes to record resource configurations in the security-tooling
    # account. Null (default) uses the AWSServiceRoleForConfig service-linked role (created unless
    # create_config_service_linked_role = false).
    config_role_arn = optional(string)
    # With config_role_arn = null, create the AWSServiceRoleForConfig service-linked role in the
    # security-tooling account. Set false if Config was ever enabled there (the SLR already exists).
    create_config_service_linked_role = optional(bool, true)
    # ARN of an existing IAM role the Config organization aggregator assumes. Null (default) creates
    # aws-config-org-aggregator in the security-tooling account with the AWSConfigRoleForOrganizations
    # managed policy.
    aggregator_role_arn = optional(string)
    # ARN of an existing AmazonSecurityLakeMetaStoreManager role. Empty (default) with
    # enable_security_lake: the stage creates AmazonSecurityLakeMetaStoreManagerV2 in the security-
    # tooling account (with the tfc-apply boundary).
    meta_store_manager_role_arn = optional(string, "")
    # ARN of an EXTERNALLY-managed break-glass role to watch for assumption. Ignored when
    # create_break_glass is true (the stage then creates and watches its own role). Any AssumeRole
    # against the effective ARN raises a notification.
    break_glass_role_arn = optional(string, "")
    # Set of org-security services (org-security-service module) to enable: any of macie, inspector,
    # detective, resource-explorer. Detective defaults OFF per SRA.
    enabled_security_services = optional(set(string), ["macie", "inspector"])
    # Master COST toggle for Amazon Security Lake. Security Lake incurs ingestion, storage, and
    # normalization charges.
    enable_security_lake = optional(bool, true)
    # AWS Config records ALL supported resource types (default true — the full-coverage but most
    # expensive Config mode). Set false for cost-sensitive non-prod (FinOps F5).
    config_record_all_supported = optional(bool, true)
    # GuardDuty agentless EBS malware scanning (default true; billed per GB scanned). Set false for
    # non-prod where it is not required (FinOps F5).
    guardduty_enable_ebs_malware_protection = optional(bool, true)
    # Master switch for the incident-response automation (isolation Lambda, GuardDuty EventBridge
    # rule, forensics snapshot-sharing role).
    enable_incident_response = optional(bool, true)
    # Master switch for service-quota management (opt-in). When false, no quota requests or usage
    # alarms are created.
    enable_service_quotas = optional(bool, false)
    # Subscribers attached to the security-notifications SNS topic, keyed by an arbitrary name. At
    # least one is required (findings would otherwise fire into a void). Defaults to a placeholder
    # SecOps email the root is expected to override.
    notification_subscribers = optional(map(object({
      protocol = string # one of: email, https, sms, sqs, lambda, etc.
      endpoint = string # e.g. an email address or HTTPS URL
      })), {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    })
    # Dedicated identity account for IAM Identity Center delegated administration. Default null = the
    # shared-services account (unchanged). Set to a dedicated identity account to tighten the
    # delegated-admin blast radius. PREVIEW: opt-in (default off), not yet validated against a real
    # apply.
    identity_account_id = optional(string)
    # Attach a CloudWatch Logs group to the org trail and create the full CIS AWS section-4 metric-
    # filter alarm set (4.1-4.15) with a KMS-encrypted SNS topic, all in the management account. Self-
    # sufficient: a logs-granted CMK is created when cloudwatch_logs_kms_key_arn is null. Default
    # true; set false for S3-only delivery.
    enable_cloudwatch_logs = optional(bool, true)
    # Retention (days) for the CloudTrail CloudWatch Logs group when enable_cloudwatch_logs = true.
    cloudwatch_logs_retention_days = optional(number, 365)
    # Optional existing CMK ARN (management account) for the CloudTrail CloudWatch Logs group and CIS
    # alarm topic; its policy must grant logs.<region>.amazonaws.com and cloudwatch.amazonaws.com.
    # Null (default) = a dedicated CMK is created.
    cloudwatch_logs_kms_key_arn = optional(string)
    # Optional existing SNS topic ARN for the CIS alarms. Null (default) = a KMS-encrypted topic is
    # created and subscribed with cloudtrail_alarm_subscribers.
    cloudtrail_alarm_sns_topic_arn = optional(string)
    # Subscribers of the CIS alarm topic. Null (default) = reuse notification_subscribers.
    cloudtrail_alarm_subscribers = optional(map(object({
      protocol = string
      endpoint = string
    })))
    # CIS alarm keys to skip (see modules/aws/security/cloudtrail-org cis_alarms_excluded), e.g.
    # ["unauthorized-api-calls"] if too noisy org-wide.
    cloudtrail_cis_alarms_excluded = optional(list(string), [])
    # S3 object-level data events on the org trail: none, write (CIS 3.8, default), read (CIS 3.9) or
    # all. COST: billed per event across every org account.
    cloudtrail_s3_data_events = optional(string, "write")
    # Extra S3 bucket ARNs excluded from data events (the log-archive bucket is always excluded).
    cloudtrail_s3_data_events_excluded_bucket_arns = optional(list(string), [])
    # Record Lambda Invoke data events on the org trail (default false; per-invocation cost).
    cloudtrail_lambda_data_events = optional(bool, false)
    # Create and manage the break-glass role in the management account (opt-in), instead of
    # referencing an external one. When true the role's ARN is wired into the assumption alarm
    # automatically and exported.
    create_break_glass = optional(bool, false)
    # Name of the managed break-glass role (used only when create_break_glass is true). Its ARN is
    # arn:aws:iam::<management-account>:role/<this name> — set the org SCP exemptions to match.
    break_glass_role_name = optional(string, "OrganizationBreakGlass")
    # Account-qualified ARNs permitted to assume the managed break-glass role (used only when
    # create_break_glass is true). Keep this to a small set of senior responders. MFA is always
    # required.
    break_glass_trusted_principals = optional(list(string), [])
    # Maximum age in seconds of the MFA session allowed to assume the managed break-glass role (used
    # only when create_break_glass is true).
    break_glass_mfa_max_age = optional(number, 3600)
    # Set true ONLY during a declared incident to attach AdministratorAccess to the managed break-
    # glass role. False (default) keeps the deny-all standing policy. Flipping this to true should
    # itself be a reviewed, alarmed change.
    break_glass_active = optional(bool, false)
    # Create the organization CloudTrail (management account) with its CloudWatch Logs, CIS alarms and
    # KMS wiring. Set false when another owner already runs the org trail, e.g. AWS Control Tower
    # (docs/runbooks/aws-brownfield-adoption.md); two org trails double the cost and the noise.
    # Default true.
    create_organization_trail = optional(bool, true)
    # Existing CloudTrail -> CloudWatch Logs delivery role (created by aws-organization,
    # create_org_trail_delivery_role). Null = the cloudtrail-org module creates it, which needs IAM
    # write in the management account.
    cloudtrail_cloudwatch_role_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.aws.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions (aws.enabled_regions in config/landing-zone.yaml) must contain at least one Region."
  }

  validation {
    condition     = length(var.aws.aws_enabled_regions) == length(distinct(var.aws.aws_enabled_regions))
    error_message = "aws_enabled_regions (aws.enabled_regions in config/landing-zone.yaml) must not contain duplicate Regions."
  }

  validation {
    condition     = length(trimspace(coalesce(var.aws.log_archive_bucket_name, " "))) > 0
    error_message = "log_archive_bucket_name is unset: set aws.log_archive_bucket_name in config/landing-zone.yaml (or aws_overrides.log_archive_bucket_name in the aws-security root) to a non-empty S3 bucket name."
  }

  validation {
    condition     = var.aws.key_admin_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", coalesce(var.aws.key_admin_arn, "x")))
    error_message = "key_admin_arn must be null or an account-qualified IAM role/user ARN."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_/-]{1,64}$", var.aws.key_admin_role_name))
    error_message = "key_admin_role_name must be a valid IAM role name."
  }

  validation {
    condition     = alltrue([for k in keys(var.aws.kms_key_user_arns) : contains(["log_archive", "forensics", "security_tooling"], k)])
    error_message = "kms_key_user_arns keys must be one of log_archive, forensics, security_tooling."
  }

  validation {
    condition     = var.aws.config_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.aws.config_role_arn, "x")))
    error_message = "config_role_arn must be null or an account-qualified IAM role ARN."
  }

  validation {
    condition     = var.aws.aggregator_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.aws.aggregator_role_arn, "x")))
    error_message = "aggregator_role_arn must be null or an account-qualified IAM role ARN."
  }

  validation {
    condition     = var.aws.meta_store_manager_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.aws.meta_store_manager_role_arn))
    error_message = "meta_store_manager_role_arn must be empty (create the role) or a valid IAM role ARN."
  }

  validation {
    condition     = var.aws.break_glass_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.aws.break_glass_role_arn))
    error_message = "break_glass_role_arn must be empty or an account-qualified IAM role ARN."
  }

  validation {
    condition = alltrue([
      for s in var.aws.enabled_security_services : contains(["macie", "inspector", "detective", "resource-explorer"], s)
    ])
    error_message = "enabled_security_services entries must be one of: macie, inspector, detective, resource-explorer."
  }

  validation {
    condition     = length(var.aws.notification_subscribers) > 0
    error_message = "notification_subscribers must contain at least one subscriber."
  }

  validation {
    condition     = contains(["none", "write", "read", "all"], var.aws.cloudtrail_s3_data_events)
    error_message = "cloudtrail_s3_data_events must be one of: none, write, read, all."
  }

  validation {
    condition     = !var.aws.create_break_glass || length(var.aws.break_glass_trusted_principals) > 0
    error_message = "create_break_glass = true requires at least one break_glass_trusted_principals entry (an empty trust policy is rejected by AWS)."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.aws.break_glass_role_name))
    error_message = "break_glass_role_name must be a valid IAM role name (1-64 chars of A-Z a-z 0-9 +=,.@_-)."
  }

  validation {
    condition     = alltrue([for p in var.aws.break_glass_trusted_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:", p))])
    error_message = "Each break_glass_trusted_principals entry must be an account-qualified IAM ARN (arn:aws:iam::<12-digit>:...)."
  }

  validation {
    condition     = var.aws.break_glass_mfa_max_age >= 300 && var.aws.break_glass_mfa_max_age <= 43200
    error_message = "break_glass_mfa_max_age must be between 300 and 43200 seconds."
  }
}

# -----------------------------------------------------------------------------
# Naming + IAM carve-out ARNs
# -----------------------------------------------------------------------------

variable "key_policy_admin_role_name" {
  description = "Role name (optionally path-prefixed), in each CMK's OWN account, granted kms:PutKeyPolicy — and nothing else — on the log-archive, forensics and security-tooling CMKs. Default break-glass: the member break-glass role the aws-organization stage deploys to every member account (enable_member_break_glass_role), so the pipeline key admin cannot rewrite a key policy to grant itself kms:Decrypt. The role must exist before this stage creates the keys (KMS rejects unknown principals), and later key-policy changes must be applied as it. Null = legacy: key admin also holds PutKeyPolicy."
  type        = string
  default     = "break-glass"

  validation {
    condition     = var.key_policy_admin_role_name == null || can(regex("^([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]{1,64}$", coalesce(var.key_policy_admin_role_name, "x")))
    error_message = "key_policy_admin_role_name must be null or an IAM role name without wildcards (optionally path-prefixed)."
  }
}

variable "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch Logs group the organization CloudTrail delivers into, in the security-tooling account. When set (with break_glass_role_arn), the security-notifications control adds a metric-filter + CloudWatch metric ALARM on break-glass AssumeRole. Empty (default) leaves only the always-on EventBridge rule."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Service toggles + notification config
# -----------------------------------------------------------------------------

variable "quarantine_vpc_id" {
  description = "VPC ID in which the incident-response deny-all quarantine security group is created. Empty (default) skips the SG. Supply the VPC holding the workloads the isolation Lambda may need to quarantine."
  type        = string
  default     = ""

  validation {
    condition     = var.quarantine_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.quarantine_vpc_id))
    error_message = "quarantine_vpc_id must be empty or a valid VPC id of the form vpc-xxxxxxxx."
  }
}

variable "enable_firewall_manager" {
  description = "Master switch for AWS Firewall Manager composition. Default false: registering the FMS administrator is an explicit, one-time decision, and the firewall-manager-org module ships a placeholder security-group policy that must be overridden before enabling. When true, the Security Tooling account is registered as FMS admin from the management account."
  type        = bool
  default     = false
}

# --- Dedicated IAM Identity Center account (opt-in, default = unchanged) ---

# --- CloudTrail: CloudWatch Logs + CIS section-4 alarms, data events (CIS 3.8/3.9) ---

variable "cloudwatch_logs_kms_key_manager_arns" {
  description = "IAM role ARNs granted day-2 management (refresh, rotation, tags, aliases) of the module-created CloudWatch Logs CMK by its key policy. Null (default) = the aws-security management apply role (<management_role_name_prefix>aws-security-apply) in the management account. [] = none."
  type        = list(string)
  default     = null
}

variable "management_role_name_prefix" {
  description = "Prefix of the management-account tfc-management-roles role names, used to derive the aws-security apply role ARN when cloudwatch_logs_kms_key_manager_arns is null. Must match the aws-organization tfc_management_roles role_name_prefix."
  type        = string
  default     = "tfc-mgmt-"
}

# -----------------------------------------------------------------------------
# Managed break-glass role
#
# When create_break_glass is true, the stage creates the emergency-access role
# itself (MFA-gated trust, deny-all standing policy, AdministratorAccess only
# while break_glass_active) in the management account, and feeds its ARN into the
# assumption alarm automatically. This turns the break-glass principal from an
# unmanaged ARN string into a managed, monitored resource. Default false keeps the
# previous behaviour: pass an externally-managed break_glass_role_arn.
# -----------------------------------------------------------------------------

variable "tfc_apply_boundary_policy_name" {
  description = "Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply_boundary_policy_name). Every IAM role this stage creates in the security-tooling account (Config aggregator, incident-response roles; management-account roles are unaffected) gets permissions_boundary = arn:PARTITION:iam::ACCOUNT_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary."
  type        = string
  default     = "tfc-apply-boundary"

  validation {
    condition     = var.tfc_apply_boundary_policy_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.tfc_apply_boundary_policy_name))
    error_message = "tfc_apply_boundary_policy_name must be null or a valid IAM policy name (1-128 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn) for the ARNs this stage builds when the security-tooling partition is not read."
  type        = string
  default     = "aws"
}

variable "backup_account_id" {
  description = "Dedicated backup account, registered as the AWS Backup delegated administrator. Null = the security-tooling account."
  type        = string
  default     = null
}
