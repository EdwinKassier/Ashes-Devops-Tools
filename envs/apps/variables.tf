variable "project_prefix" {
  description = "Short name prefix used by the organization root. Must match the organization root's project_prefix exactly — used for resource naming consistency."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = <<-EOT
    Application environment to deploy. Must match a key in the organization root's
    `environments` map (e.g., "dev", "staging", "prod"). A mismatch causes a
    plan-time failure when looking up environment_config[var.environment].
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with optional hyphens (e.g., 'dev', 'staging', 'prod')."
  }
}

variable "provider_region" {
  description = "Default provider region for the Google provider"
  type        = string
  default     = "europe-west1"
}

variable "terraform_admin_email" {
  description = "Optional service account email to impersonate for local runs (format: name@project.iam.gserviceaccount.com)"
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a valid email address when provided."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used to read organization remote state"
  type        = string
}

variable "organization_workspace_name" {
  description = "Workspace name that stores the organization root state"
  type        = string
  default     = "organization"
}

variable "monthly_budget_limit" {
  description = "Monthly budget for this application environment"
  type        = number
  default     = 0
}

variable "budget_currency" {
  description = "ISO 4217 currency code for budget alerts (e.g., USD, EUR, GBP)"
  type        = string
  default     = "USD"

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget_currency))
    error_message = "budget_currency must be a 3-letter ISO 4217 currency code (e.g., USD, EUR)."
  }
}

variable "enable_deletion_protection" {
  description = "Enable lifecycle protection to prevent accidental destruction of critical network resources (VPC, subnets, DNS zones). Set to false only during teardown — requires state manipulation before destroy. See docs/runbooks/cidr-expansion.md for the removal procedure."
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for internet-facing workloads"
  type        = bool
  default     = false
}

variable "enable_owasp_rules" {
  description = "Enable Cloud Armor OWASP managed rules"
  type        = bool
  default     = false
}

variable "enable_adaptive_protection" {
  description = "Enable Cloud Armor adaptive protection"
  type        = bool
  default     = false
}

variable "owasp_sensitivity" {
  description = "Cloud Armor OWASP managed rule sensitivity level: 1 = strictest (most blocks, lowest false-negative rate), 4 = most permissive (fewest blocks, highest false-negative rate). Default 2 is recommended for production."
  type        = number
  default     = 2

  validation {
    condition     = var.owasp_sensitivity >= 1 && var.owasp_sensitivity <= 4
    error_message = "owasp_sensitivity must be between 1 (strictest) and 4 (most permissive)."
  }
}

variable "log_config_flow_sampling" {
  description = "VPC Flow Logs packet-sampling rate (0.0–1.0). 0.1 = 10% of packets sampled. Recommended: 0.5 for dev/staging, 0.1 for prod (reduce Logging cost). Set to 0.0 to disable flow log collection while keeping the log bucket."
  type        = number
  default     = 0.1

  validation {
    condition     = var.log_config_flow_sampling >= 0.0 && var.log_config_flow_sampling <= 1.0
    error_message = "log_config_flow_sampling must be between 0.0 and 1.0."
  }
}

variable "log_config_aggregation_interval" {
  description = "VPC Flow Logs aggregation interval"
  type        = string
  default     = "INTERVAL_5_SEC"
}

variable "vpc_flow_logs_retention_days" {
  description = "Retention period for exported VPC flow logs"
  type        = number
  default     = 30
}

variable "extra_labels" {
  description = "Additional labels applied to the host project resources"
  type        = map(string)
  default     = {}
}

variable "vpc_sc_enable_dry_run" {
  description = <<-EOT
    When true, VPC Service Controls logs violations but does NOT block any traffic (dry-run/simulation mode).
    When false (the default), the perimeter is in ENFORCED mode and will block unauthorised cross-perimeter traffic.

    WARNING: dry-run mode provides NO data-exfiltration protection. Only use true temporarily to
    validate that no legitimate traffic will be blocked before switching to enforcement.
    See docs/architecture/network-topology.md for the enforcement transition procedure.
  EOT
  type        = bool
  default     = false
}

variable "vpc_sc_perimeter_title" {
  description = "Optional title override for the VPC-SC perimeter"
  type        = string
  default     = null
}

variable "vpc_sc_restricted_services" {
  description = "Restricted services enforced by the VPC-SC perimeter"
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "pubsub.googleapis.com",
    "sqladmin.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

variable "vpc_sc_ingress_policies" {
  description = "Optional ingress policies for the VPC-SC perimeter"
  type = list(object({
    identity_type = optional(string)
    identities    = optional(list(string))
    sources = optional(list(object({
      access_level = optional(string)
      resource     = optional(string)
    })))
    resources = optional(list(string))
    operations = optional(list(object({
      service_name = string
      method_selectors = optional(list(object({
        method     = optional(string)
        permission = optional(string)
      })))
    })))
  }))
  default = []
}

variable "vpc_sc_egress_policies" {
  description = "Optional egress policies for the VPC-SC perimeter"
  type = list(object({
    identity_type = optional(string)
    identities    = optional(list(string))
    resources     = optional(list(string))
    operations = optional(list(object({
      service_name = string
      method_selectors = optional(list(object({
        method     = optional(string)
        permission = optional(string)
      })))
    })))
  }))
  default = []
}
