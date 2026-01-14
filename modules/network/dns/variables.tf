/**
 * Copyright 2023 Ashes
 *
 * Cloud DNS Module - Variables
 */

variable "project_id" {
  description = "The project ID where the DNS zone will be created"
  type        = string
}

variable "zone_name" {
  description = "Name of the DNS zone (used as resource identifier)"
  type        = string
}

variable "dns_name" {
  description = "The DNS name of this managed zone (e.g., 'internal.company.com.')"
  type        = string

  validation {
    condition     = can(regex("\\.$", var.dns_name))
    error_message = "DNS name must end with a trailing dot (e.g., 'example.com.')."
  }
}

variable "description" {
  description = "Description of the DNS zone"
  type        = string
  default     = "Private DNS zone managed by Terraform"
}

variable "visibility" {
  description = "Zone visibility: 'public' or 'private'"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private"], var.visibility)
    error_message = "Visibility must be 'public' or 'private'."
  }
}

variable "private_visibility_networks" {
  description = "List of VPC network self-links that can see this private zone"
  type        = list(string)
  default     = []
}

variable "peering_network" {
  description = "The target VPC network for a peering zone (required when type is 'peering')"
  type        = string
  default     = ""
}

variable "records" {
  description = "DNS records to create in the zone"
  type = list(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    rrdatas = list(string)
  }))
  default = []
}

variable "dnssec_enabled" {
  description = "Enable DNSSEC for the zone (supports both public and private zones)"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enable query logging for the zone"
  type        = bool
  default     = false
}

variable "forwarding_targets" {
  description = "List of forwarding target IP addresses (for forwarding zones)"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the DNS zone"
  type        = map(string)
  default     = {}
}
