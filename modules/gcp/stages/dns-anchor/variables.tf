/**
 * Copyright 2023 Ashes
 *
 * dns-anchor Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID that owns the network (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "The primary GCP region of the network (e.g., 'us-central1', 'europe-west1')."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region name (e.g., 'us-central1', 'europe-west1')."
  }
}

variable "labels" {
  description = "Labels applied to every labelable resource."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Guard the VPC and subnet stack with a prevent_destroy terraform_data resource and enable VPC deletion protection. To deprovision deliberately, first run terraform state rm on the network module guard."
  type        = bool
  default     = false
}

variable "network" {
  description = <<-EOT
    The VPC and its three-tier zonal subnet layout.
    name and cidr_block are required. Pin explicit_zones for production: when
    empty, zones are discovered from GCP and a change in the returned zone set
    re-derives the subnet CIDRs (replacing subnets). subnet_cidrs lists are
    index-aligned with the zones; an empty list derives that tier from
    cidr_block. The anchor VPC hosts no workloads; the subnets keep the
    layout uniform with the hub and spokes. flow_logs sets the subnet flow-log
    sampling.
  EOT
  type = object({
    name           = string
    cidr_block     = string
    explicit_zones = optional(list(string), [])
    subnet_cidrs = optional(object({
      public   = optional(list(string), [])
      private  = optional(list(string), [])
      database = optional(list(string), [])
    }), {})
    flow_logs = optional(object({
      aggregation_interval = optional(string, "INTERVAL_5_SEC")
      sampling             = optional(number, 0.5)
    }), {})
  })

  validation {
    condition     = can(cidrnetmask(var.network.cidr_block)) ? cidrhost(var.network.cidr_block, 0) == split("/", var.network.cidr_block)[0] : false
    error_message = "network.cidr_block must be valid CIDR notation without host bits set (e.g. \"10.0.0.0/16\")."
  }
  validation {
    condition     = alltrue([for z in var.network.explicit_zones : can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", z))])
    error_message = "Each entry in network.explicit_zones must be a valid GCP zone name (e.g. 'us-central1-a')."
  }
}

variable "firewall" {
  description = "Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database."
  type = object({
    enable_logging     = optional(bool, true)
    enable_iap_access  = optional(bool, true)
    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])
    database_ports     = optional(list(string), ["3306", "5432", "6379"])
  })
  default  = {}
  nullable = false
}

variable "dns_zones" {
  description = <<-EOT
    Private Cloud DNS zones anchored on this VPC, keyed by zone name. dns_name
    must end with a dot. Every zone is bound to the anchor VPC; add other
    networks via additional_visibility_networks. DNSSEC defaults on and query
    logging is always on.
  EOT
  type = map(object({
    dns_name                       = string
    description                    = optional(string)
    dnssec_enabled                 = optional(bool, true)
    additional_visibility_networks = optional(list(string), [])
    records = optional(list(object({
      name    = string
      type    = string
      ttl     = optional(number, 300)
      rrdatas = list(string)
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for z in values(var.dns_zones) : endswith(z.dns_name, ".")])
    error_message = "Each dns_zones[*].dns_name must be a fully qualified name ending with a dot (e.g. internal.example.com.)."
  }
}

variable "peerings" {
  description = "VPC peerings from this network, keyed by peering name (the anchor is normally reached by DNS peering, not VPC peering)."
  type = map(object({
    peer_network           = string
    create_reverse_peering = optional(bool, true)
    export_custom_routes   = optional(bool, false)
    import_custom_routes   = optional(bool, false)
  }))
  default  = {}
  nullable = false
}
