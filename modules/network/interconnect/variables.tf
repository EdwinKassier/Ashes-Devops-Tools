/**
 * Copyright 2023 Ashes
 *
 * Cloud Interconnect Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region for the interconnect attachment"
  type        = string
}

variable "network" {
  description = "The VPC network self_link or ID"
  type        = string
}

variable "attachment_name" {
  description = "Name for the interconnect attachment (VLAN)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.attachment_name))
    error_message = "Attachment name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "interconnect_type" {
  description = "Type of interconnect: DEDICATED or PARTNER"
  type        = string
  default     = "PARTNER"

  validation {
    condition     = contains(["DEDICATED", "PARTNER"], var.interconnect_type)
    error_message = "Interconnect type must be DEDICATED or PARTNER."
  }
}

variable "description" {
  description = "Description of the interconnect attachment"
  type        = string
  default     = "Managed by Terraform"
}

# -----------------------------------------------------------------------------
# Router Configuration
# -----------------------------------------------------------------------------

variable "create_router" {
  description = "Whether to create a new Cloud Router"
  type        = bool
  default     = true
}

variable "router_name" {
  description = "Name of the Cloud Router"
  type        = string
}

variable "router_asn" {
  description = "BGP ASN for the Cloud Router"
  type        = number
  default     = 64512
}

variable "advertised_groups" {
  description = "Advertised groups for the router (e.g., ALL_SUBNETS)"
  type        = list(string)
  default     = ["ALL_SUBNETS"]
}

variable "advertised_ip_ranges" {
  description = "Custom IP ranges to advertise via BGP"
  type = list(object({
    range       = string
    description = optional(string)
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Dedicated Interconnect Configuration
# -----------------------------------------------------------------------------

variable "interconnect_self_link" {
  description = "Self-link of the Dedicated Interconnect (required for DEDICATED type)"
  type        = string
  default     = null
}

variable "vlan_tag" {
  description = "802.1Q VLAN tag for dedicated interconnect (1-4094)"
  type        = number
  default     = null

  validation {
    condition     = var.vlan_tag == null || (var.vlan_tag >= 1 && var.vlan_tag <= 4094)
    error_message = "VLAN tag must be between 1 and 4094."
  }
}

variable "bandwidth" {
  description = "Provisioned bandwidth for dedicated interconnect (e.g., BPS_1G, BPS_10G)"
  type        = string
  default     = "BPS_10G"
}

variable "candidate_subnets" {
  description = "Candidate subnets for auto-assigned IP addresses (CIDR format)"
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# Partner Interconnect Configuration
# -----------------------------------------------------------------------------

variable "edge_availability_domain" {
  description = "Edge availability domain for partner interconnect (AVAILABILITY_DOMAIN_1 or AVAILABILITY_DOMAIN_2)"
  type        = string
  default     = "AVAILABILITY_DOMAIN_1"

  validation {
    condition     = contains(["AVAILABILITY_DOMAIN_1", "AVAILABILITY_DOMAIN_2", "AVAILABILITY_DOMAIN_ANY"], var.edge_availability_domain)
    error_message = "Edge availability domain must be AVAILABILITY_DOMAIN_1, AVAILABILITY_DOMAIN_2, or AVAILABILITY_DOMAIN_ANY."
  }
}

# -----------------------------------------------------------------------------
# Common Attachment Settings
# -----------------------------------------------------------------------------

variable "mtu" {
  description = "Maximum Transmission Unit (MTU) for the attachment"
  type        = number
  default     = 1440

  validation {
    condition     = contains([1440, 1460, 1500, 8896], var.mtu)
    error_message = "MTU must be 1440, 1460, 1500, or 8896."
  }
}

variable "admin_enabled" {
  description = "Whether the VLAN attachment is enabled"
  type        = bool
  default     = true
}

variable "encryption" {
  description = "Encryption mode: NONE or IPSEC"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "IPSEC"], var.encryption)
    error_message = "Encryption must be NONE or IPSEC."
  }
}

# -----------------------------------------------------------------------------
# BGP Peering Configuration
# -----------------------------------------------------------------------------

variable "create_bgp_peer" {
  description = "Whether to create BGP peering configuration"
  type        = bool
  default     = true
}

variable "interface_ip_range" {
  description = "IP range for the router interface (CIDR format, /29 or /30)"
  type        = string
  default     = null
}

variable "peer_ip_address" {
  description = "IP address of the on-premises BGP peer"
  type        = string
  default     = null
}

variable "peer_asn" {
  description = "BGP ASN of the on-premises router"
  type        = number
  default     = 65000
}

variable "advertised_route_priority" {
  description = "Priority for advertised routes (lower = higher priority)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# BFD Configuration (Bidirectional Forwarding Detection)
# -----------------------------------------------------------------------------

variable "enable_bfd" {
  description = "Enable BFD for fast failover detection"
  type        = bool
  default     = false
}

variable "bfd_session_initialization_mode" {
  description = "BFD session initialization mode: ACTIVE, PASSIVE, or DISABLED"
  type        = string
  default     = "ACTIVE"
}

variable "bfd_min_transmit_interval" {
  description = "Minimum BFD transmit interval in milliseconds"
  type        = number
  default     = 1000
}

variable "bfd_min_receive_interval" {
  description = "Minimum BFD receive interval in milliseconds"
  type        = number
  default     = 1000
}

variable "bfd_multiplier" {
  description = "BFD detection multiplier"
  type        = number
  default     = 5
}
