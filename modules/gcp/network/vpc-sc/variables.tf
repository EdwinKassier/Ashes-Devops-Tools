/**
 * Copyright 2023 Ashes
 *
 * VPC Service Controls Module - Variables
 */

variable "organization_id" {
  description = "The organization ID in full resource form (e.g., 'organizations/123456789'). NOTE: unlike other repo modules (governance/tags, governance/cloud-audit-logs) which take a bare numeric org id, this module requires the 'organizations/' prefix because it is passed directly to the Access Context Manager access-policy parent. Callers holding a bare numeric id (e.g. the organization stage output) must prefix it."
  type        = string

  validation {
    condition     = can(regex("^organizations/[0-9]+$", var.organization_id))
    error_message = "Organization ID must be in format 'organizations/ID'."
  }
}

variable "create_access_policy" {
  description = "Whether to create a new access policy (only one per org allowed)"
  type        = bool
  default     = false
}

variable "access_policy_name" {
  description = "Numeric ID of an existing Access Context Manager access policy (required when create_access_policy is false). Must be the bare numeric policy ID, not the full resource path — e.g. '1234567890', not 'accessPolicies/1234567890'."
  type        = string
  default     = null

  validation {
    condition     = var.create_access_policy || var.access_policy_name != null
    error_message = "access_policy_name must be set when create_access_policy is false — an existing policy name is required."
  }

  validation {
    condition     = var.access_policy_name == null || can(regex("^[0-9]+$", var.access_policy_name))
    error_message = "access_policy_name must be a bare numeric policy ID (e.g. '1234567890'), not a full resource path like 'accessPolicies/...'."
  }
}

variable "access_policy_title" {
  description = "Title for the access policy (if creating new)"
  type        = string
  default     = "Organization Access Policy"
}

variable "perimeter_name" {
  description = "Name of the service perimeter"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.perimeter_name))
    error_message = "Perimeter name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "perimeter_title" {
  description = "Human-readable title for the service perimeter"
  type        = string
}

variable "description" {
  description = "Description of the service perimeter"
  type        = string
  default     = "Managed by Terraform"
}

variable "perimeter_type" {
  description = "Type of service perimeter: PERIMETER_TYPE_REGULAR or PERIMETER_TYPE_BRIDGE"
  type        = string
  default     = "PERIMETER_TYPE_REGULAR"

  validation {
    condition     = contains(["PERIMETER_TYPE_REGULAR", "PERIMETER_TYPE_BRIDGE"], var.perimeter_type)
    error_message = "Perimeter type must be PERIMETER_TYPE_REGULAR or PERIMETER_TYPE_BRIDGE."
  }
}

variable "protected_projects" {
  description = <<-EOT
    List of project numbers to protect within the perimeter.
    Use bare numeric project numbers (e.g., "123456789012") — the module prepends "projects/" automatically.
    Do NOT pass "projects/NNN" (double-wrap) or project IDs (e.g., "my-project-name").
    Get the number with: gcloud projects describe <id> --format='value(projectNumber)'
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.protected_projects : !can(regex("^projects/", p))])
    error_message = "protected_projects values must NOT include a 'projects/' prefix — the module adds it automatically. Pass bare numeric project numbers (e.g., '123456789012')."
  }
}

variable "restricted_services" {
  description = "List of GCP services to restrict (e.g., ['storage.googleapis.com', 'bigquery.googleapis.com'])"
  type        = list(string)
  default     = []
}

variable "access_levels" {
  description = "List of access levels to create"
  type = list(object({
    name               = string
    title              = string
    description        = optional(string)
    combining_function = optional(string, "AND")
    conditions = list(object({
      ip_subnetworks         = optional(list(string))
      required_access_levels = optional(list(string))
      members                = optional(list(string))
      negate                 = optional(bool, false)
      regions                = optional(list(string))
      device_policy = optional(object({
        require_screen_lock              = optional(bool)
        require_admin_approval           = optional(bool)
        require_corp_owned               = optional(bool)
        allowed_encryption_statuses      = optional(list(string))
        allowed_device_management_levels = optional(list(string))
        os_constraints = optional(list(object({
          os_type                    = string
          minimum_version            = optional(string)
          require_verified_chrome_os = optional(bool)
        })))
      }))
    }))
  }))
  default = []
}

variable "vpc_accessible_services" {
  description = "Configuration for VPC accessible services"
  type = object({
    enable_restriction = bool
    allowed_services   = list(string)
  })
  default = null
}

variable "ingress_policies" {
  description = "Ingress policies for the perimeter"
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

variable "egress_policies" {
  description = "Egress policies for the perimeter"
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

# =============================================================================
# DRY RUN MODE (Recommended for initial rollout)
# =============================================================================

variable "enable_dry_run" {
  description = <<-EOF
    Enable dry run mode for the service perimeter.
    When enabled, VPC-SC violations are logged but not enforced.
    This is recommended for initial rollout to identify potential issues before enforcement.

    Set to false once you've verified no unexpected violations occur.
  EOF
  type        = bool
  default     = false
}

# =============================================================================
# DELETION PROTECTION
# =============================================================================

variable "enable_deletion_protection" {
  description = <<-EOT
    When true, a sentinel terraform_data resource with prevent_destroy = true is
    created alongside the perimeter. Terraform will refuse to plan destruction of
    the perimeter while this sentinel exists. To tear down a protected perimeter:

      1. Set enable_deletion_protection = false and apply (removes the sentinel).
      2. Run the destroy plan in a second apply.

    IMPORTANT: Terraform's prevent_destroy is a static compile-time literal and
    cannot be passed as a variable directly on the resource. The sentinel pattern
    provides equivalent protection while remaining toggle-able without state
    surgery.
  EOT
  type        = bool
  default     = true
}
