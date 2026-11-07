# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via the TF_CLOUD_ORGANIZATION environment variable (kept out of the code so the same root works across orgs and CI). Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

variable "organization_contract" {
  description = "aws-organization stage contract (FAST-style override), the same type in every aws root: organization_id (o-xxxxxxxxxx), organization_root_id (r-xxxx), management_account_id, ou_ids (OU name => OU ID), account_ids (account key => 12-digit ID), account_role_arns (account key => cross-account role ARN). This root needs: organization_id, organization_root_id, management_account_id, account_ids, account_role_arns. When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else the contract output of the organization_workspace_name workspace."
  type = object({
    organization_id       = optional(string)
    organization_root_id  = optional(string)
    management_account_id = optional(string)
    ou_ids                = optional(map(string), {})
    account_ids           = map(string)
    account_role_arns     = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.organization_contract == null || alltrue([for id in values(try(var.organization_contract.account_ids, {})) : can(regex("^[0-9]{12}$", id))])
    error_message = "organization_contract.account_ids values must be 12-digit AWS account IDs."
  }

  validation {
    condition     = var.organization_contract == null || alltrue([for k in ["organization_id", "organization_root_id", "management_account_id"] : try(length(trimspace(var.organization_contract[k])) > 0, false)])
    error_message = "organization_contract must set organization_id, organization_root_id, management_account_id for this root."
  }
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "management_account_id" {
  description = "12-digit AWS management (payer) account ID. The default provider sets allowed_account_ids to this, so Terraform fails fast if the resolved credentials are a different account. Null = aws.management_account_id from config/landing-zone.yaml (quote it there); no built-in default."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[0-9]{12}$", coalesce(var.management_account_id, local.cfg.management_account_id, "!unset")))
    error_message = "management_account_id is unset or invalid: set var.management_account_id or aws.management_account_id in config/landing-zone.yaml (quoted) to the 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Home (aggregation) region for every provider, e.g. eu-west-2. Also the Security Hub home_region for region-scoped standard ARNs. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (or org.regions.aws in config/landing-zone.yaml) must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_overrides" {
  description = "Explicit overrides of the aws section (config/landing-zone.yaml aws.*) fed to the security stage. Every key is optional and the type is the stage's aws object: a set (non-null) key wins over the config file, an unset or null key keeps the config value (or the profile-driven default), else the stage default. Keys that are not in the config schema (key_admin_arn, create_break_glass, ...) are set only here. Precedence: aws_overrides > config/landing-zone.yaml > built-in default. See UPGRADING.md for the old variable names."
  type = object({
    aws_enabled_regions                     = optional(list(string))
    log_archive_bucket_name                 = optional(string)
    key_admin_arn                           = optional(string)
    key_admin_role_name                     = optional(string)
    kms_key_user_arns                       = optional(map(list(string)))
    enable_kms_protection_tag               = optional(bool)
    config_role_arn                         = optional(string)
    create_config_service_linked_role       = optional(bool)
    aggregator_role_arn                     = optional(string)
    meta_store_manager_role_arn             = optional(string)
    break_glass_role_arn                    = optional(string)
    enabled_security_services               = optional(set(string))
    enable_security_lake                    = optional(bool)
    config_record_all_supported             = optional(bool)
    guardduty_enable_ebs_malware_protection = optional(bool)
    enable_incident_response                = optional(bool)
    enable_service_quotas                   = optional(bool)
    enable_internal_access_analyzer         = optional(bool)
    notification_subscribers = optional(map(object({
      protocol = string # one of: email, https, sms, sqs, lambda, etc.
      endpoint = string # e.g. an email address or HTTPS URL
    })))
    identity_account_id            = optional(string)
    enable_cloudwatch_logs         = optional(bool)
    cloudwatch_logs_retention_days = optional(number)
    cloudwatch_logs_kms_key_arn    = optional(string)
    cloudtrail_alarm_sns_topic_arn = optional(string)
    cloudtrail_alarm_subscribers = optional(map(object({
      protocol = string
      endpoint = string
    })))
    cloudtrail_cis_alarms_excluded                 = optional(list(string))
    cloudtrail_s3_data_events                      = optional(string)
    cloudtrail_s3_data_events_excluded_bucket_arns = optional(list(string))
    cloudtrail_lambda_data_events                  = optional(bool)
    create_break_glass                             = optional(bool)
    break_glass_role_name                          = optional(string)
    break_glass_trusted_principals                 = optional(list(string))
    break_glass_mfa_max_age                        = optional(number)
    break_glass_active                             = optional(bool)
    create_organization_trail                      = optional(bool)
    cloudtrail_cloudwatch_role_arn                 = optional(string)
    enable_cloudtrail_delegated_admin              = optional(bool)
    cloudtrail_delegated_admin_trail_name          = optional(string)
    create_management_trail                        = optional(bool)
  })
  default  = {}
  nullable = false
}

# key_policy_admin_role_name stays its own variable: null is a meaningful value
# (legacy: the key admin also holds PutKeyPolicy), which the null-filtered
# aws_overrides merge cannot express.
variable "key_policy_admin_role_name" {
  description = "Role name, in each CMK's own account, granted kms:PutKeyPolicy (and nothing else) on the log-archive, forensics and security-tooling CMKs. Default break-glass: the member break-glass role aws-organization deploys to every member account, so the pipeline key admin cannot rewrite a key policy. It must exist before the keys are created; later key-policy changes must be applied as it. Null = legacy (key admin also holds PutKeyPolicy)."
  type        = string
  default     = "break-glass"
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
  description = "Landing-zone identifier written to the LandingZone tag on every resource. Null = org.name from config/landing-zone.yaml (the single source shared by every AWS root). The upstream placeholders \"ashes\" and \"my-org\" are rejected."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is unset or invalid: set var.landing_zone_name or org.name in config/landing-zone.yaml. It must be 2-31 chars: a lowercase letter, then lowercase letters, digits or hyphens."
  }

  validation {
    condition     = !contains(["ashes", "my-org"], lower(coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is still an upstream placeholder (ashes / my-org). Set your own landing-zone identifier."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root. Null = org.cost_center from config/landing-zone.yaml, else \"platform\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform"))) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list). Null = org.owner from config/landing-zone.yaml, else \"platform-team\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team"))) > 0
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

variable "profile" {
  description = "Cost/assurance profile: production (default; full inspection and detection stack) or starter (cheapest safe non-prod baseline). It only changes the defaults of the profile-driven toggles; any explicit toggle still wins. Null = org.profile from config/landing-zone.yaml, else production."
  type        = string
  default     = null

  validation {
    condition     = var.profile == null || contains(["production", "starter"], coalesce(var.profile, "production"))
    error_message = "profile must be production or starter."
  }
}

