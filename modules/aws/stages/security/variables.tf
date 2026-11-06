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

variable "aws_enabled_regions" {
  description = "Regions in which the regional security services (Config, GuardDuty, Security Lake) are enabled. One set of per-Region resources is created for each entry."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one Region."
  }

  validation {
    condition     = length(var.aws_enabled_regions) == length(distinct(var.aws_enabled_regions))
    error_message = "aws_enabled_regions must not contain duplicate Regions."
  }
}

# -----------------------------------------------------------------------------
# Naming + IAM carve-out ARNs
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket. Cross-root naming contract: it must match the name the log-tamper SCP references."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "key_admin_arn" {
  description = "Account-qualified ARN of the principal granted key ADMINISTRATION (management actions only: no Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant) on the log-archive, forensics and security-tooling CMKs. Null (default) grants each key's OWN account role key_admin_role_name (the TFC OIDC baseline tfc-apply role that applies this stage), e.g. arn:aws:iam::<log-archive id>:role/tfc-apply, so the keys can never be locked out of management. Grant key usage separately via kms_key_user_arns."
  type        = string
  default     = null

  validation {
    condition     = var.key_admin_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", coalesce(var.key_admin_arn, "x")))
    error_message = "key_admin_arn must be null or an account-qualified IAM role/user ARN."
  }
}

variable "key_admin_role_name" {
  description = "With key_admin_arn = null, the role name (in each CMK's own account) granted key administration. Default tfc-apply: the role the TFC OIDC baseline creates and this stage applies as, so it must already exist. Set to your own per-account admin role if you run with OrganizationAccountAccessRole instead."
  type        = string
  default     = "tfc-apply"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_/-]{1,64}$", var.key_admin_role_name))
    error_message = "key_admin_role_name must be a valid IAM role name."
  }
}

variable "key_policy_admin_role_name" {
  description = "Role name (optionally path-prefixed), in each CMK's OWN account, granted kms:PutKeyPolicy — and nothing else — on the log-archive, forensics and security-tooling CMKs. Default break-glass: the member break-glass role the aws-organization stage deploys to every member account (enable_member_break_glass_role), so the pipeline key admin cannot rewrite a key policy to grant itself kms:Decrypt. The role must exist before this stage creates the keys (KMS rejects unknown principals), and later key-policy changes must be applied as it. Null = legacy: key admin also holds PutKeyPolicy."
  type        = string
  default     = "break-glass"

  validation {
    condition     = var.key_policy_admin_role_name == null || can(regex("^([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]{1,64}$", coalesce(var.key_policy_admin_role_name, "x")))
    error_message = "key_policy_admin_role_name must be null or an IAM role name without wildcards (optionally path-prefixed)."
  }
}

variable "kms_key_user_arns" {
  description = "Principals granted key USAGE (Encrypt/Decrypt/ReEncrypt/GenerateDataKey/DescribeKey) per CMK, keyed by log_archive / forensics / security_tooling. Separate from key_admin_arn (administration only). Missing keys mean no general-usage grant beyond the built-in service-principal grants."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.kms_key_user_arns) : contains(["log_archive", "forensics", "security_tooling"], k)])
    error_message = "kms_key_user_arns keys must be one of log_archive, forensics, security_tooling."
  }
}

variable "enable_kms_protection_tag" {
  description = "Tag the log-archive, forensics and security-tooling CMKs protected = \"true\" so the organization deny-tamper SCP blocks key deletion/disablement and protection-tag removal except via break-glass. Default true."
  type        = bool
  default     = true
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in the security-tooling account. Null (default) uses the AWSServiceRoleForConfig service-linked role (created unless create_config_service_linked_role = false)."
  type        = string
  default     = null

  validation {
    condition     = var.config_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.config_role_arn, "x")))
    error_message = "config_role_arn must be null or an account-qualified IAM role ARN."
  }
}

variable "create_config_service_linked_role" {
  description = "With config_role_arn = null, create the AWSServiceRoleForConfig service-linked role in the security-tooling account. Set false if Config was ever enabled there (the SLR already exists)."
  type        = bool
  default     = true
}

variable "aggregator_role_arn" {
  description = "ARN of an existing IAM role the Config organization aggregator assumes. Null (default) creates aws-config-org-aggregator in the security-tooling account with the AWSConfigRoleForOrganizations managed policy."
  type        = string
  default     = null

  validation {
    condition     = var.aggregator_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.aggregator_role_arn, "x")))
    error_message = "aggregator_role_arn must be null or an account-qualified IAM role ARN."
  }
}

variable "meta_store_manager_role_arn" {
  description = "ARN of the AmazonSecurityLakeMetaStoreManager IAM role Security Lake uses to manage the Lake Formation metastore. Required when enable_security_lake is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_security_lake || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.meta_store_manager_role_arn))
    error_message = "meta_store_manager_role_arn must be a valid IAM role ARN when enable_security_lake is true."
  }
}

variable "break_glass_role_arn" {
  description = "ARN of an EXTERNALLY-managed break-glass role to watch for assumption. Ignored when create_break_glass is true (the stage then creates and watches its own role). Any AssumeRole against the effective ARN raises a notification."
  type        = string
  default     = ""

  validation {
    condition     = var.break_glass_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must be empty or an account-qualified IAM role ARN."
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

variable "enabled_security_services" {
  description = "Set of org-security services (org-security-service module) to enable: any of macie, inspector, detective, resource-explorer. Detective defaults OFF per SRA."
  type        = set(string)
  default     = ["macie", "inspector"]

  validation {
    condition = alltrue([
      for s in var.enabled_security_services : contains(["macie", "inspector", "detective", "resource-explorer"], s)
    ])
    error_message = "enabled_security_services entries must be one of: macie, inspector, detective, resource-explorer."
  }
}

variable "enable_security_lake" {
  description = "Master COST toggle for Amazon Security Lake. Security Lake incurs ingestion, storage, and normalization charges."
  type        = bool
  default     = true
}

variable "config_record_all_supported" {
  description = "AWS Config records ALL supported resource types (default true — the full-coverage but most expensive Config mode). Set false for cost-sensitive non-prod (FinOps F5)."
  type        = bool
  default     = true
}

variable "guardduty_enable_ebs_malware_protection" {
  description = "GuardDuty agentless EBS malware scanning (default true; billed per GB scanned). Set false for non-prod where it is not required (FinOps F5)."
  type        = bool
  default     = true
}

variable "enable_incident_response" {
  description = "Master switch for the incident-response automation (isolation Lambda, GuardDuty EventBridge rule, forensics snapshot-sharing role)."
  type        = bool
  default     = true
}

variable "quarantine_vpc_id" {
  description = "VPC ID in which the incident-response deny-all quarantine security group is created. Empty (default) skips the SG. Supply the VPC holding the workloads the isolation Lambda may need to quarantine."
  type        = string
  default     = ""

  validation {
    condition     = var.quarantine_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.quarantine_vpc_id))
    error_message = "quarantine_vpc_id must be empty or a valid VPC id of the form vpc-xxxxxxxx."
  }
}

variable "enable_service_quotas" {
  description = "Master switch for service-quota management (opt-in). When false, no quota requests or usage alarms are created."
  type        = bool
  default     = false
}

variable "enable_firewall_manager" {
  description = "Master switch for AWS Firewall Manager composition. Default false: registering the FMS administrator is an explicit, one-time decision, and the firewall-manager-org module ships a placeholder security-group policy that must be overridden before enabling. When true, the Security Tooling account is registered as FMS admin from the management account."
  type        = bool
  default     = false
}

variable "notification_subscribers" {
  description = "Subscribers attached to the security-notifications SNS topic, keyed by an arbitrary name. At least one is required (findings would otherwise fire into a void). Defaults to a placeholder SecOps email the root is expected to override."
  type = map(object({
    protocol = string # one of: email, https, sms, sqs, lambda, etc.
    endpoint = string # e.g. an email address or HTTPS URL
  }))
  default = {
    secops = { protocol = "email", endpoint = "secops@example.com" }
  }

  validation {
    condition     = length(var.notification_subscribers) > 0
    error_message = "notification_subscribers must contain at least one subscriber."
  }
}

# --- Audit finding A3: dedicated IAM Identity Center account (opt-in, default = unchanged) ---
variable "identity_account_id" {
  description = "Dedicated identity account for IAM Identity Center delegated administration. Default null = the shared-services account (unchanged). Set to a dedicated identity account to tighten the delegated-admin blast radius. PREVIEW: opt-in (default off), not yet validated against a real apply."
  type        = string
  default     = null
}

# --- CloudTrail: CloudWatch Logs + CIS section-4 alarms, data events (CIS 3.8/3.9) ---
variable "enable_cloudwatch_logs" {
  description = "Attach a CloudWatch Logs group to the org trail and create the full CIS AWS section-4 metric-filter alarm set (4.1-4.15) with a KMS-encrypted SNS topic, all in the management account. Self-sufficient: a logs-granted CMK is created when cloudwatch_logs_kms_key_arn is null. Default true; set false for S3-only delivery."
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "Retention (days) for the CloudTrail CloudWatch Logs group when enable_cloudwatch_logs = true."
  type        = number
  default     = 365
}

variable "cloudwatch_logs_kms_key_arn" {
  description = "Optional existing CMK ARN (management account) for the CloudTrail CloudWatch Logs group and CIS alarm topic; its policy must grant logs.<region>.amazonaws.com and cloudwatch.amazonaws.com. Null (default) = a dedicated CMK is created."
  type        = string
  default     = null
}

variable "cloudtrail_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN for the CIS alarms. Null (default) = a KMS-encrypted topic is created and subscribed with cloudtrail_alarm_subscribers."
  type        = string
  default     = null
}

variable "cloudtrail_alarm_subscribers" {
  description = "Subscribers of the CIS alarm topic. Null (default) = reuse notification_subscribers."
  type = map(object({
    protocol = string
    endpoint = string
  }))
  default = null
}

variable "cloudtrail_cis_alarms_excluded" {
  description = "CIS alarm keys to skip (see modules/aws/security/cloudtrail-org cis_alarms_excluded), e.g. [\"unauthorized-api-calls\"] if too noisy org-wide."
  type        = list(string)
  default     = []
}

variable "cloudtrail_s3_data_events" {
  description = "S3 object-level data events on the org trail: none, write (CIS 3.8, default), read (CIS 3.9) or all. COST: billed per event across every org account."
  type        = string
  default     = "write"

  validation {
    condition     = contains(["none", "write", "read", "all"], var.cloudtrail_s3_data_events)
    error_message = "cloudtrail_s3_data_events must be one of: none, write, read, all."
  }
}

variable "cloudtrail_s3_data_events_excluded_bucket_arns" {
  description = "Extra S3 bucket ARNs excluded from data events (the log-archive bucket is always excluded)."
  type        = list(string)
  default     = []
}

variable "cloudtrail_lambda_data_events" {
  description = "Record Lambda Invoke data events on the org trail (default false; per-invocation cost)."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Managed break-glass role (audit M3)
#
# When create_break_glass is true, the stage creates the emergency-access role
# itself (MFA-gated trust, deny-all standing policy, AdministratorAccess only
# while break_glass_active) in the management account, and feeds its ARN into the
# assumption alarm automatically. This turns the break-glass principal from an
# unmanaged ARN string into a managed, monitored resource. Default false keeps the
# previous behaviour: pass an externally-managed break_glass_role_arn.
# -----------------------------------------------------------------------------

variable "create_break_glass" {
  description = "Create and manage the break-glass role in the management account (opt-in), instead of referencing an external one. When true the role's ARN is wired into the assumption alarm automatically and exported."
  type        = bool
  default     = false

  validation {
    condition     = !var.create_break_glass || length(var.break_glass_trusted_principals) > 0
    error_message = "create_break_glass = true requires at least one break_glass_trusted_principals entry (an empty trust policy is rejected by AWS)."
  }
}

variable "break_glass_role_name" {
  description = "Name of the managed break-glass role (used only when create_break_glass is true). Its ARN is arn:aws:iam::<management-account>:role/<this name> — set the org SCP exemptions to match."
  type        = string
  default     = "OrganizationBreakGlass"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.break_glass_role_name))
    error_message = "break_glass_role_name must be a valid IAM role name (1-64 chars of A-Z a-z 0-9 +=,.@_-)."
  }
}

variable "break_glass_trusted_principals" {
  description = "Account-qualified ARNs permitted to assume the managed break-glass role (used only when create_break_glass is true). Keep this to a small set of senior responders. MFA is always required."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.break_glass_trusted_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:", p))])
    error_message = "Each break_glass_trusted_principals entry must be an account-qualified IAM ARN (arn:aws:iam::<12-digit>:...)."
  }
}

variable "break_glass_mfa_max_age" {
  description = "Maximum age in seconds of the MFA session allowed to assume the managed break-glass role (used only when create_break_glass is true)."
  type        = number
  default     = 3600

  validation {
    condition     = var.break_glass_mfa_max_age >= 300 && var.break_glass_mfa_max_age <= 43200
    error_message = "break_glass_mfa_max_age must be between 300 and 43200 seconds."
  }
}

variable "break_glass_active" {
  description = "Set true ONLY during a declared incident to attach AdministratorAccess to the managed break-glass role. False (default) keeps the deny-all standing policy. Flipping this to true should itself be a reviewed, alarmed change."
  type        = bool
  default     = false
}

variable "tfc_apply_boundary_policy_name" {
  description = "Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply_boundary_policy_name). Every IAM role this stage creates in the security-tooling account (Config aggregator, incident-response roles; management-account roles are unaffected) gets permissions_boundary = arn:PARTITION:iam::ACCOUNT_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary."
  type        = string
  default     = "tfc-apply-boundary"

  validation {
    condition     = var.tfc_apply_boundary_policy_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.tfc_apply_boundary_policy_name))
    error_message = "tfc_apply_boundary_policy_name must be null or a valid IAM policy name (1-128 chars of [A-Za-z0-9+=,.@_-])."
  }
}
