/**
 * Copyright 2023 Ashes
 *
 * Tiered VPC Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID that owns the VPC (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "name" {
  description = "Name of the VPC network. Also the prefix of every subnet, firewall rule and guard derived by this module."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be a valid RFC 1035 VPC name: 1-63 characters, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Region of the zonal subnet layout (e.g. us-central1)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region name (e.g., 'us-central1', 'europe-west1')."
  }
}

variable "cidr_block" {
  description = "The VPC CIDR block (e.g. 10.0.0.0/16). Per-tier subnets are carved from it unless subnet_cidrs is set."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid CIDR notation (e.g. \"10.0.0.0/16\")."
  }
  validation {
    condition     = can(cidrnetmask(var.cidr_block)) ? cidrhost(var.cidr_block, 0) == split("/", var.cidr_block)[0] : true
    error_message = "cidr_block must not have host bits set (e.g. use \"10.0.0.0/16\", not \"10.0.1.0/16\")."
  }
}

variable "zones" {
  description = "Zones of the subnet layout; one subnet per tier is created per zone, keyed by zone name. Pin these for production: changing the zone set re-derives the CIDRs and replaces subnets."
  type        = list(string)

  validation {
    condition     = length(var.zones) > 0
    error_message = "zones must contain at least one zone."
  }
}

variable "subnet_cidrs" {
  description = "Explicit per-tier subnet CIDRs (index-aligned with zones). An empty list derives that tier from cidr_block."
  type = object({
    public   = optional(list(string), [])
    private  = optional(list(string), [])
    database = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for tier in [var.subnet_cidrs.public, var.subnet_cidrs.private, var.subnet_cidrs.database] :
      length(tier) == 0 || length(tier) >= length(var.zones)
    ])
    error_message = "Each non-empty subnet_cidrs list must have at least as many entries as zones (or be empty to derive the tier from cidr_block)."
  }
}

variable "secondary_ranges" {
  description = "Secondary IP ranges for the private (compute) subnets, keyed by zone name (GKE Pods and Services)."
  type = map(list(object({
    range_name    = string
    ip_cidr_range = string
  })))
  default  = {}
  nullable = false
}

variable "shared_vpc_host" {
  description = "Enable the owning project as a Shared VPC host."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Create a prevent_destroy guard that blocks any plan destroying the VPC and subnet stack, and enable VPC deletion protection."
  type        = bool
  default     = false
}

variable "flow_logs" {
  description = "Subnet VPC flow-log settings applied to every tier (flow logs are always on)."
  type = object({
    aggregation_interval = optional(string, "INTERVAL_5_SEC")
    sampling             = optional(number, 0.5)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["INTERVAL_5_SEC", "INTERVAL_30_SEC", "INTERVAL_1_MIN", "INTERVAL_5_MIN", "INTERVAL_10_MIN", "INTERVAL_15_MIN"], var.flow_logs.aggregation_interval)
    error_message = "flow_logs.aggregation_interval must be one of INTERVAL_5_SEC, INTERVAL_30_SEC, INTERVAL_1_MIN, INTERVAL_5_MIN, INTERVAL_10_MIN, INTERVAL_15_MIN."
  }
  validation {
    condition     = var.flow_logs.sampling >= 0.0 && var.flow_logs.sampling <= 1.0
    error_message = "flow_logs.sampling must be between 0.0 and 1.0 inclusive."
  }
}

variable "firewall" {
  description = "Baseline tier firewall settings: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database. api_gateway_source_ranges (the CIDRs API Gateway traffic arrives from) and database_egress_target_service_accounts apply only to the network firewall policy (firewall_mode both / policy); the API Gateway policy rule is created only when api_gateway_source_ranges is non-empty."
  type = object({
    enable_logging                          = optional(bool, true)
    enable_iap_access                       = optional(bool, true)
    compute_tier_ports                      = optional(list(string), ["8080", "8443", "3000"])
    database_ports                          = optional(list(string), ["3306", "5432", "6379"])
    api_gateway_source_ranges               = optional(list(string), [])
    database_egress_target_service_accounts = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "firewall_mode" {
  description = "How the baseline tier firewall is enforced. legacy: tag-based VPC firewall rules (default). both: the VPC rules plus one global network firewall policy whose rules select tiers by subnet CIDR (the migration step). policy: the network firewall policy only; the VPC rules are removed. See docs/runbooks/gcp-firewall-policy-migration.md."
  type        = string
  default     = "legacy"
  nullable    = false

  validation {
    condition     = contains(["legacy", "both", "policy"], var.firewall_mode)
    error_message = "firewall_mode must be one of legacy, both or policy."
  }
}

variable "firewall_policy_enforcement_order" {
  description = "Network firewall policy enforcement order on the VPC: BEFORE_CLASSIC_FIREWALL or AFTER_CLASSIC_FIREWALL. null derives it from firewall_mode: policy sets BEFORE_CLASSIC_FIREWALL; legacy and both leave it unset (API default AFTER_CLASSIC_FIREWALL). Updates the network in place. WARNING: switching from both to policy with this unset flips the order in the same apply that deletes the legacy rules; set it explicitly (a check warns when it is unset in policy mode)."
  type        = string
  default     = null

  validation {
    condition     = var.firewall_policy_enforcement_order == null ? true : contains(["BEFORE_CLASSIC_FIREWALL", "AFTER_CLASSIC_FIREWALL"], var.firewall_policy_enforcement_order)
    error_message = "firewall_policy_enforcement_order must be null, BEFORE_CLASSIC_FIREWALL or AFTER_CLASSIC_FIREWALL."
  }
}
