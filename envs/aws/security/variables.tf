# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "management_account_id" {
  description = "12-digit AWS management (payer) account ID. The default provider sets allowed_account_ids to this, so Terraform fails fast if the resolved credentials are a different account (audit C4). No default: admins must state their own payer account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Home (aggregation) region for every provider, e.g. eu-west-2. Also the Security Hub home_region for region-scoped standard ARNs."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions in which the regional security services (Config, GuardDuty, Security Lake) are enabled. One set of per-region resources is created for each entry."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }
}

# -----------------------------------------------------------------------------
# Naming + IAM carve-out ARNs (operator-supplied)
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket. Cross-root naming contract: it MUST match the name the log-tamper SCP references in the aws-organization root."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "key_admin_arn" {
  description = "Account-qualified ARN of the principal granted key ADMINISTRATION (management actions only: no Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant) on the log-archive, forensics and security-tooling CMKs. Null (default) grants each key's own account role key_admin_role_name (tfc-apply, the role this root applies as under TFC dynamic credentials). Grant key usage separately via kms_key_user_arns."
  type        = string
  default     = null

  validation {
    condition     = var.key_admin_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", coalesce(var.key_admin_arn, "x")))
    error_message = "key_admin_arn must be null or an account-qualified IAM role/user ARN."
  }
}

variable "key_admin_role_name" {
  description = "With key_admin_arn = null, the role name in each CMK's own account granted key administration. Default tfc-apply (created by the aws-organization TFC OIDC baseline). Set it to an existing per-account admin role if you run the legacy OrganizationAccountAccessRole path with the baseline disabled."
  type        = string
  default     = "tfc-apply"
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
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in the security-tooling account. Null (default) uses the AWSServiceRoleForConfig service-linked role, created by this root unless create_config_service_linked_role = false."
  type        = string
  default     = null

  validation {
    condition     = var.config_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.config_role_arn, "x")))
    error_message = "config_role_arn must be null or an account-qualified IAM role ARN."
  }
}

variable "create_config_service_linked_role" {
  description = "With config_role_arn = null, create AWSServiceRoleForConfig in the security-tooling account. Set false if Config was ever enabled there (the service-linked role already exists)."
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
  description = "ARN of the break-glass IAM role the security-notifications control watches for assumption. Any AssumeRole against this ARN raises a notification. Empty disables the watch."
  type        = string
  default     = ""

  validation {
    condition     = var.break_glass_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must be empty or an account-qualified IAM role ARN."
  }
}

# -----------------------------------------------------------------------------
# Service toggles + notification config
# -----------------------------------------------------------------------------

variable "notification_subscribers" {
  description = "Subscribers attached to the security-notifications SNS topic, keyed by an arbitrary name. At least one is required. Defaults to a placeholder SecOps email the root is expected to override."
  type = map(object({
    protocol = string # "email" | "https" | "sms" | "sqs" | "lambda" | ...
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

variable "enabled_security_services" {
  description = "Set of org-security services to enable: any of macie, inspector, detective, resource-explorer. Detective defaults OFF per SRA."
  type        = set(string)
  default     = ["macie", "inspector"]

  validation {
    condition = alltrue([
      for s in var.enabled_security_services : contains(["macie", "inspector", "detective", "resource-explorer"], s)
    ])
    error_message = "enabled_security_services entries must be one of: macie, inspector, detective, resource-explorer."
  }
}

variable "config_record_all_supported" {
  description = "AWS Config records ALL supported resource types (default true — the full-coverage but most expensive Config mode). Set false for cost-sensitive non-prod (FinOps F5). See examples/presets/nonprod-aws-security.tfvars."
  type        = bool
  default     = true
}

variable "guardduty_enable_ebs_malware_protection" {
  description = "GuardDuty agentless EBS malware scanning (default true; billed per GB scanned). Set false for non-prod where it is not required (FinOps F5)."
  type        = bool
  default     = true
}

variable "enable_security_lake" {
  description = "Master COST toggle for Amazon Security Lake. Security Lake incurs ingestion, storage, and normalization charges."
  type        = bool
  default     = true
}

variable "enable_incident_response" {
  description = "Master switch for the incident-response automation (isolation Lambda, GuardDuty EventBridge rule, forensics snapshot-sharing role)."
  type        = bool
  default     = true
}

variable "enable_service_quotas" {
  description = "Master switch for service-quota management (opt-in). When false, no quota requests or usage alarms are created."
  type        = bool
  default     = false
}

# --- Audit finding A3: dedicated IAM Identity Center account (opt-in, default = unchanged) ---
variable "identity_account_id" {
  description = "Dedicated identity account for IAM Identity Center delegated admin. Default null = shared-services account (unchanged). PREVIEW (not yet validated against a real apply)."
  type        = string
  default     = null
}

# --- CloudTrail: CIS section-4 alarms (CloudWatch Logs) + S3 data events (CIS 3.8/3.9) ---
variable "enable_cloudwatch_logs" {
  description = "Attach a CloudWatch Logs group to the org trail and create the full CIS AWS section-4 metric-filter alarm set with a KMS-encrypted SNS topic (management account). Self-sufficient: a logs-granted CMK is created unless cloudwatch_logs_kms_key_arn is set. Default true; false = S3-only."
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "Retention (days) for the CloudTrail CloudWatch Logs group when enable_cloudwatch_logs = true."
  type        = number
  default     = 365
}

variable "cloudwatch_logs_kms_key_arn" {
  description = "Optional existing CMK (management account) for the CloudTrail log group and CIS alarm topic; must grant logs.<region>.amazonaws.com and cloudwatch.amazonaws.com. Null (default) = a dedicated CMK is created."
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
  description = "CIS alarm keys to skip, e.g. [\"unauthorized-api-calls\"] if too noisy org-wide."
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
# Managed break-glass role (audit M3) — opt-in passthrough to the security stage.
# -----------------------------------------------------------------------------

variable "create_break_glass" {
  description = "Create and manage the break-glass role in the management account (opt-in). When true, break_glass_role_arn is ignored and the stage-created role's ARN is watched and exported."
  type        = bool
  default     = false
}

variable "break_glass_role_name" {
  description = "Name of the managed break-glass role (used only when create_break_glass is true). Set the org SCP exemption to arn:aws:iam::<management-account>:role/<this name>."
  type        = string
  default     = "OrganizationBreakGlass"
}

variable "break_glass_trusted_principals" {
  description = "Account-qualified ARNs permitted to assume the managed break-glass role (used only when create_break_glass is true). Keep small; MFA is always required."
  type        = list(string)
  default     = []
}

variable "break_glass_mfa_max_age" {
  description = "Maximum MFA session age in seconds allowed to assume the managed break-glass role (used only when create_break_glass is true)."
  type        = number
  default     = 3600
}

variable "break_glass_active" {
  description = "Set true ONLY during a declared incident to attach AdministratorAccess to the managed break-glass role. False keeps the deny-all standing policy."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Tagging — provider default_tags (FinOps / governance)
#
# Every resource the aws provider(s) in this root create gets the canonical tag
# set: CostCenter / Environment / Owner (the keys the tag policy enforces and
# cost-governance activates as cost-allocation tags) plus ManagedBy /
# LandingZone / Workspace. default_tags is merged LAST, so it can add keys or
# override any canonical value.
# -----------------------------------------------------------------------------

variable "landing_zone_name" {
  description = "Landing-zone identifier written to the LandingZone tag on every resource. No default: set your own organization's identifier (same value in every AWS root; set it once in the tfc-admin common variable set via common_workspace_variables). The upstream placeholders \"ashes\" and \"my-org\" are rejected."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.landing_zone_name))
    error_message = "landing_zone_name must be 2-31 chars: a lowercase letter, then lowercase letters, digits or hyphens."
  }

  validation {
    condition     = !contains(["ashes", "my-org"], lower(var.landing_zone_name))
    error_message = "landing_zone_name is still an upstream placeholder (ashes / my-org). Set your own landing-zone identifier."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root."
  type        = string
  default     = "platform"

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list)."
  type        = string
  default     = "platform-team"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "default_tags" {
  description = "Extra tags merged into the aws provider default_tags (after the canonical set, so they may override it). Values must be non-empty."
  type        = map(string)
  default     = {}

  validation {
    # An empty-string default tag makes the provider plan a perpetual diff.
    condition     = alltrue([for v in values(var.default_tags) : length(trimspace(v)) > 0])
    error_message = "default_tags values must be non-empty strings."
  }
}

# -----------------------------------------------------------------------------
# Credentials — TFC multi-configuration dynamic credentials
# -----------------------------------------------------------------------------

variable "tfc_aws_dynamic_credentials" {
  description = "Injected by Terraform Cloud when the workspace uses AWS dynamic credentials with multiple configurations: default = the management-account role, aliases[security_tooling, log_archive, forensics] = each member account's tfc-plan / tfc-apply role (TFC_AWS_PROVIDER_AUTH_<alias>, TFC_AWS_PLAN_ROLE_ARN_<alias>, TFC_AWS_APPLY_ROLE_ARN_<alias>). Leave null for local / legacy runs: the member-account providers then assume account_role_arns (OrganizationAccountAccessRole) from management-account credentials."
  type = object({
    default = object({ shared_config_file = string })
    aliases = map(object({ shared_config_file = string }))
  })
  default = null
}
