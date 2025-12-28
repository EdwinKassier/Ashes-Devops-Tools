/**
 * Copyright 2023 Ashes
 *
 * VPC Peering Module - Variables
 */

variable "project_id" {
  description = "The project ID where the peering will be created"
  type        = string
}

variable "peering_name" {
  description = "Name of the VPC peering connection"
  type        = string
}

variable "network" {
  description = "The self-link of the local VPC network"
  type        = string
}

variable "peer_network" {
  description = "The self-link of the peer VPC network"
  type        = string
}

variable "export_custom_routes" {
  description = "Export custom routes to the peer network"
  type        = bool
  default     = false
}

variable "import_custom_routes" {
  description = "Import custom routes from the peer network"
  type        = bool
  default     = false
}

variable "export_subnet_routes_with_public_ip" {
  description = "Export subnet routes with public IP range to the peer network"
  type        = bool
  default     = true
}

variable "import_subnet_routes_with_public_ip" {
  description = "Import subnet routes with public IP range from the peer network"
  type        = bool
  default     = false
}

variable "stack_type" {
  description = "The stack type for the peering (IPV4_ONLY or IPV4_IPV6)"
  type        = string
  default     = "IPV4_ONLY"

  validation {
    condition     = contains(["IPV4_ONLY", "IPV4_IPV6"], var.stack_type)
    error_message = "Stack type must be 'IPV4_ONLY' or 'IPV4_IPV6'."
  }
}

variable "create_reverse_peering" {
  description = "Create the reverse peering connection (for bi-directional peering)"
  type        = bool
  default     = true
}

variable "peer_project_id" {
  description = "The project ID of the peer network (if different from project_id)"
  type        = string
  default     = null
}
