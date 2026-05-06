variable "project_prefix" {
  description = "Prefix used by the organization root"
  type        = string
  default     = "my-org"
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
  description = "Optional service account to impersonate for local runs"
  type        = string
  default     = null
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
  description = "Budget currency code"
  type        = string
  default     = "USD"
}

variable "enable_deletion_protection" {
  description = "Enable lifecycle protection for critical resources"
  type        = bool
  default     = false
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
  description = "Cloud Armor OWASP sensitivity (1 is strictest, 4 is least strict)"
  type        = number
  default     = 4
}

variable "log_config_flow_sampling" {
  description = "VPC Flow Logs sampling rate"
  type        = number
  default     = 0.1
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
  description = "Whether the VPC-SC perimeter should run in dry-run mode"
  type        = bool
  default     = true
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
