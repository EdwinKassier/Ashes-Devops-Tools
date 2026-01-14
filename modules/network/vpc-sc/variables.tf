/**
 * Copyright 2023 Ashes
 *
 * VPC Service Controls Module - Variables
 */

variable "organization_id" {
  description = "The organization ID (e.g., 'organizations/123456789')"
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
  description = "Existing access policy name (required if create_access_policy is false)"
  type        = string
  default     = null
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
  description = "List of project numbers to protect within the perimeter"
  type        = list(string)
  default     = []
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
