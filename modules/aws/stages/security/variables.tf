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
  description = "Account-qualified ARN of the principal granted key administration (kms:*) on both the log and forensics CMKs. REQUIRED to avoid locking the keys out of management."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", var.key_admin_arn))
    error_message = "key_admin_arn must be an account-qualified IAM role/user ARN."
  }
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in each account/Region."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.config_role_arn))
    error_message = "config_role_arn must be an account-qualified IAM role ARN."
  }
}

variable "aggregator_role_arn" {
  description = "ARN of the IAM role the Config organization aggregator assumes to collect Config data across the organization."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.aggregator_role_arn))
    error_message = "aggregator_role_arn must be an account-qualified IAM role ARN."
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
  description = "ARN of the break-glass IAM role the security-notifications control watches for assumption. Any AssumeRole against this ARN raises a notification."
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
