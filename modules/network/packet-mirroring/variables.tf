/**
 * Copyright 2023 Ashes
 *
 * Packet Mirroring Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name" {
  description = "Name of the packet mirroring policy"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "Name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The region for the packet mirroring policy"
  type        = string
}

variable "description" {
  description = "Description of the packet mirroring policy"
  type        = string
  default     = "Managed by Terraform"
}

variable "network" {
  description = "The VPC network self_link or ID"
  type        = string
}

variable "collector_ilb_url" {
  description = "The URL of the internal load balancer to collect mirrored traffic"
  type        = string
}

# -----------------------------------------------------------------------------
# Mirrored Resources
# -----------------------------------------------------------------------------

variable "mirrored_instances" {
  description = "List of instance self_links to mirror traffic from"
  type        = list(string)
  default     = []
}

variable "mirrored_subnetworks" {
  description = "List of subnetwork self_links to mirror traffic from"
  type        = list(string)
  default     = []
}

variable "mirrored_tags" {
  description = "List of network tags to identify instances for mirroring"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Filter Configuration
# -----------------------------------------------------------------------------

variable "filter_ip_protocols" {
  description = "IP protocols to mirror (e.g., ['tcp', 'udp', 'icmp'])"
  type        = list(string)
  default     = []
}

variable "filter_cidr_ranges" {
  description = "CIDR ranges to filter (traffic matching these ranges will be mirrored)"
  type        = list(string)
  default     = []
}

variable "filter_direction" {
  description = "Direction of traffic to mirror: INGRESS, EGRESS, or BOTH"
  type        = string
  default     = "BOTH"

  validation {
    condition     = contains(["INGRESS", "EGRESS", "BOTH"], var.filter_direction)
    error_message = "Filter direction must be INGRESS, EGRESS, or BOTH."
  }
}

# -----------------------------------------------------------------------------
# Policy Settings
# -----------------------------------------------------------------------------

variable "priority" {
  description = "Priority of the mirroring policy (lower = higher priority)"
  type        = number
  default     = 1000

  validation {
    condition     = var.priority >= 0 && var.priority <= 65535
    error_message = "Priority must be between 0 and 65535."
  }
}

variable "enable" {
  description = "Whether the packet mirroring policy is enabled"
  type        = bool
  default     = true
}
