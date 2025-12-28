/**
 * Copyright 2023 Ashes
 *
 * Cloud VPN Module - Variables
 */

variable "project_id" {
  description = "The project ID where the VPN will be created"
  type        = string
}

variable "name" {
  description = "Base name for VPN resources"
  type        = string
}

variable "network" {
  description = "The self-link of the VPC network"
  type        = string
}

variable "region" {
  description = "The region for the VPN gateway"
  type        = string
}

variable "router_name" {
  description = "Name of the Cloud Router (created if not exists)"
  type        = string
  default     = null
}

variable "router_asn" {
  description = "The ASN for the Cloud Router (BGP)"
  type        = number
  default     = 64514
}

variable "peer_external_gateway_ip" {
  description = "External IP address of the peer VPN gateway"
  type        = string
}

variable "peer_asn" {
  description = "The ASN of the peer network (for BGP)"
  type        = number
  default     = 65001
}

variable "shared_secret" {
  description = "Shared secret for IKE authentication"
  type        = string
  sensitive   = true
}

variable "tunnel_count" {
  description = "Number of VPN tunnels to create (1 or 2 for HA)"
  type        = number
  default     = 2

  validation {
    condition     = var.tunnel_count >= 1 && var.tunnel_count <= 2
    error_message = "Tunnel count must be 1 or 2."
  }
}

variable "peer_ip_addresses" {
  description = "List of BGP peer IP addresses for each tunnel"
  type        = list(string)
  default     = ["169.254.0.2", "169.254.1.2"]
}

variable "local_ip_addresses" {
  description = "List of local BGP IP addresses for each tunnel"
  type        = list(string)
  default     = ["169.254.0.1", "169.254.1.1"]
}

variable "advertised_ip_ranges" {
  description = "Custom IP ranges to advertise via BGP"
  type = list(object({
    range       = string
    description = optional(string)
  }))
  default = []
}

variable "labels" {
  description = "Labels to apply to VPN resources"
  type        = map(string)
  default     = {}
}
