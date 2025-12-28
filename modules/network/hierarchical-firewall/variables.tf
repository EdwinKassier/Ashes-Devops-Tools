/**
 * Copyright 2023 Ashes
 *
 * Hierarchical Firewall Policy Module - Variables
 */

variable "parent" {
  description = "The parent organization or folder (e.g., 'organizations/123456789' or 'folders/123456789')"
  type        = string

  validation {
    condition     = can(regex("^(organizations|folders)/[0-9]+$", var.parent))
    error_message = "Parent must be in format 'organizations/ID' or 'folders/ID'."
  }
}

variable "policy_name" {
  description = "Short name for the hierarchical firewall policy"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.policy_name))
    error_message = "Policy name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be at most 63 characters."
  }
}

variable "description" {
  description = "Description of the firewall policy"
  type        = string
  default     = "Managed by Terraform"
}

variable "rules" {
  description = "List of firewall policy rules"
  type = list(object({
    priority       = number
    action         = string # "allow", "deny", "goto_next"
    direction      = string # "INGRESS" or "EGRESS"
    description    = optional(string)
    disabled       = optional(bool, false)
    enable_logging = optional(bool, false)

    layer4_configs = list(object({
      ip_protocol = string
      ports       = optional(list(string))
    }))

    # Source filters (for INGRESS)
    src_ip_ranges            = optional(list(string))
    src_fqdns                = optional(list(string))
    src_region_codes         = optional(list(string))
    src_threat_intelligences = optional(list(string))

    # Destination filters (for EGRESS)
    dest_ip_ranges            = optional(list(string))
    dest_fqdns                = optional(list(string))
    dest_region_codes         = optional(list(string))
    dest_threat_intelligences = optional(list(string))

    # Targets
    target_networks         = optional(list(string))
    target_service_accounts = optional(list(string))
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.rules : contains(["allow", "deny", "goto_next"], r.action)])
    error_message = "Rule action must be 'allow', 'deny', or 'goto_next'."
  }

  validation {
    condition     = alltrue([for r in var.rules : contains(["INGRESS", "EGRESS"], r.direction)])
    error_message = "Rule direction must be 'INGRESS' or 'EGRESS'."
  }
}

variable "associations" {
  description = "List of folder or organization resource IDs to attach this policy to"
  type        = list(string)
  default     = []
}

variable "enable_logging" {
  description = "Default logging setting for rules (can be overridden per rule)"
  type        = bool
  default     = true
}
