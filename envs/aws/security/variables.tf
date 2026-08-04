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
  description = "Account-qualified ARN of the principal granted key administration (kms:*) on both the log and forensics CMKs. REQUIRED to avoid locking the keys out of management."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", var.key_admin_arn))
    error_message = "key_admin_arn must be an account-qualified IAM role/user ARN."
  }
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in each account/region."
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
