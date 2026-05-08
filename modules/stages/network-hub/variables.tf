variable "project_prefix" {
  description = "Prefix used for project naming"
  type        = string
}

variable "hub_vpc_cidr_block" {
  description = "CIDR block for the hub VPC (e.g. \"10.0.0.0/16\"). Required — set via IPAM or per-environment tfvars."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.hub_vpc_cidr_block))
    error_message = "hub_vpc_cidr_block must be a valid CIDR notation."
  }
}

variable "dns_hub_vpc_cidr_block" {
  description = "CIDR block for the DNS hub VPC (e.g. \"10.1.0.0/16\"). Required — must not overlap with hub_vpc_cidr_block."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.dns_hub_vpc_cidr_block))
    error_message = "dns_hub_vpc_cidr_block must be a valid CIDR notation."
  }
}

variable "default_region" {
  description = "Default GCP region for resources"
  type        = string
}

variable "hub_project_id" {
  description = "Project ID for the network hub"
  type        = string
}

variable "dns_project_id" {
  description = "Project ID for the DNS hub"
  type        = string
}

variable "spoke_project_ids" {
  description = "Map of spoke project IDs to attach to Shared VPC"
  type        = map(string)
}

variable "org_id" {
  description = <<-EOT
    The GCP organization ID. Accepts either a bare numeric ID (e.g. '123456789012') as returned
    by data.google_organization.org.org_id, or the 'organizations/<id>' prefixed form.
    The module normalizes to the prefixed form internally before passing to VPC-SC.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id)) || can(regex("^organizations/[0-9]+$", var.org_id))
    error_message = "org_id must be either a bare numeric ID (e.g., '123456789012') or 'organizations/<numeric_id>'."
  }
}

variable "folders" {
  description = "Map of folder objects to attach policies to"
  type = map(object({
    id           = string
    name         = string
    display_name = string
  }))
}

variable "internal_domain" {
  description = "Internal domain for private DNS zone (e.g., 'mycompany.com')"
  type        = string
  default     = "internal.local"
}

variable "vpc_sc_access_policy_name" {
  description = <<-EOT
    Bare numeric ID of the existing organisation-level Access Context Manager access policy
    (e.g. '1234567890'). Required when the hub VPC-SC perimeter is enabled.
    Do NOT include the 'accessPolicies/' prefix.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_name == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_name))
    error_message = "vpc_sc_access_policy_name must be a bare numeric ID (e.g. '1234567890'). Do not include the 'accessPolicies/' prefix."
  }
}

variable "vpc_sc_enable_dry_run" {
  description = <<-EOT
    When true, the hub VPC-SC perimeter logs violations but does NOT block traffic (dry-run/simulation mode).
    When false (the default), the perimeter is ENFORCED.
    Only set to true temporarily during the enforcement transition validation window.
  EOT
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = <<-EOT
    When true (the default), protects hub and DNS VPC resources from accidental deletion via
    terraform destroy. Set to false only during a planned teardown.
    IMPORTANT: Set to false and apply before attempting to destroy the hub network stack.
  EOT
  type        = bool
  default     = true
}
