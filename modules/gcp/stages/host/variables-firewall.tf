# Host stage (firewall) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# ADDITIONAL FIREWALL RULES CONFIGURATION
# =============================================================================

variable "existing_network_name" {
  description = "Name of existing network (when enable_networking is false)"
  type        = string
  default     = ""
}

variable "additional_firewall_rules" {
  description = "Map of additional firewall rules to create outside of the VPC module"
  type = map(object({
    direction   = optional(string, "INGRESS")
    description = optional(string)
    priority    = optional(number, 1000)
    allow_rules = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
    deny_rules = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
    source_ranges = optional(list(string))
    target_tags   = optional(list(string))
    source_tags   = optional(list(string))
  }))
  default = {}
}

# =============================================================================
# HIERARCHICAL FIREWALL POLICY CONFIGURATION
# =============================================================================

variable "hierarchical_firewall_policies" {
  description = "Map of hierarchical firewall policies to create at org/folder level"
  type = map(object({
    parent      = string
    description = optional(string, "Managed by Terraform")
    rules = optional(list(object({
      priority       = number
      action         = string
      direction      = string
      description    = optional(string)
      disabled       = optional(bool, false)
      enable_logging = optional(bool, false)
      layer4_configs = list(object({
        ip_protocol = string
        ports       = optional(list(string))
      }))
      src_ip_ranges           = optional(list(string))
      src_region_codes        = optional(list(string))
      dest_ip_ranges          = optional(list(string))
      dest_region_codes       = optional(list(string))
      target_networks         = optional(list(string))
      target_service_accounts = optional(list(string))
    })), [])
    associations   = optional(list(string), [])
    enable_logging = optional(bool, true)
  }))
  default = {}
}

