/**
 * Copyright 2023 Ashes
 *
 * NCC Spoke Module - Variables
 */

variable "project_id" {
  description = "Project that owns the spoke (the project of the linked VPC or VPN tunnels)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits or hyphens, starting with a letter)."
  }
}

variable "name" {
  description = "Spoke name. Producer spokes are named <name>-<producer_vpc_networks key>."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be 1-63 lowercase letters, digits or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "description" {
  description = "Spoke description."
  type        = string
  default     = "Network Connectivity Center spoke managed by Terraform"
}

variable "labels" {
  description = "Labels applied to the spoke and its producer spokes."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "hub_id" {
  description = "ID of the hub to attach to (network/ncc-hub id: projects/<project>/locations/global/hubs/<name>)."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/locations/global/hubs/[^/]+$", var.hub_id))
    error_message = "hub_id must be a hub ID of the form projects/<project>/locations/global/hubs/<name>."
  }
}

variable "group" {
  description = "Hub group the spoke joins. STAR hubs: center (the hub VPC) or edge (spoke VPCs). MESH hubs: default."
  type        = string
  default     = "edge"
  nullable    = false

  validation {
    condition     = contains(["center", "edge", "default"], var.group)
    error_message = "group must be center or edge (STAR hub) or default (MESH hub)."
  }
}

variable "location" {
  description = "Spoke location: global for a VPC spoke, the tunnels' region for a VPN spoke."
  type        = string
  default     = "global"
  nullable    = false

  validation {
    condition     = (var.linked_vpc_network == null) == (var.location != "global")
    error_message = "A VPC spoke (linked_vpc_network) must use location = global; a VPN spoke (linked_vpn_tunnels) must use the tunnels' region."
  }
}

variable "linked_vpc_network" {
  description = "VPC network to link (uri = the network self link). Set exactly one of linked_vpc_network or linked_vpn_tunnels. Export ranges filter which subnet ranges the hub learns."
  type = object({
    uri                   = string
    include_export_ranges = optional(list(string), [])
    exclude_export_ranges = optional(list(string), [])
  })
  default = null

  validation {
    condition     = (var.linked_vpc_network == null) != (var.linked_vpn_tunnels == null)
    error_message = "Set exactly one of linked_vpc_network or linked_vpn_tunnels."
  }
}

variable "linked_vpn_tunnels" {
  description = "HA VPN tunnels to link (self links, all in var.location). site_to_site_data_transfer must stay false unless the region supports it and data transfer between sites is intended."
  type = object({
    uris                       = list(string)
    site_to_site_data_transfer = optional(bool, false)
    include_import_ranges      = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.linked_vpn_tunnels == null || length(try(var.linked_vpn_tunnels.uris, [])) > 0
    error_message = "linked_vpn_tunnels.uris must list at least one tunnel."
  }
}

variable "producer_vpc_networks" {
  description = "Producer VPC spokes for the linked VPC's Private Service Access peerings, keyed by a short name (for example psa). network = the consumer VPC name; peering = the service networking peering name (google_service_networking_connection.<x>.peering). Requires linked_vpc_network; each joins the same group as the VPC spoke."
  type = map(object({
    network               = string
    peering               = string
    include_export_ranges = optional(list(string), [])
    exclude_export_ranges = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.producer_vpc_networks) == 0 || var.linked_vpc_network != null
    error_message = "producer_vpc_networks requires linked_vpc_network: a producer spoke must sit beside its consumer VPC spoke."
  }
  validation {
    condition     = alltrue([for k in keys(var.producer_vpc_networks) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "producer_vpc_networks keys must be 1-20 lowercase letters, digits or hyphens, starting with a letter (they suffix the spoke name)."
  }
}
