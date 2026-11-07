/**
 * Copyright 2023 Ashes
 *
 * NCC Hub Module - Variables
 */

variable "project_id" {
  description = "Project that owns the hub (normally the network hub project)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits or hyphens, starting with a letter)."
  }
}

variable "name" {
  description = "Hub name."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be 1-63 lowercase letters, digits or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "description" {
  description = "Hub description."
  type        = string
  default     = "Network Connectivity Center hub managed by Terraform"
}

variable "preset_topology" {
  description = "Preset connectivity topology. STAR: edge spokes reach the center group only (hub-and-spoke isolation, the peering-equivalent). MESH: every spoke reaches every other spoke. Immutable: changing it replaces the hub."
  type        = string
  default     = "STAR"
  nullable    = false

  validation {
    condition     = contains(["STAR", "MESH"], var.preset_topology)
    error_message = "preset_topology must be STAR or MESH."
  }
}

variable "export_psc" {
  description = "Propagate Private Service Connect endpoint connections across the hub's VPC spokes."
  type        = bool
  default     = false
  nullable    = false
}

variable "labels" {
  description = "Labels applied to the hub."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "auto_accept_projects" {
  description = "Project IDs or numbers whose spokes the spoke group (edge, or default on MESH) accepts automatically. Spokes from any other project than the hub's wait for a manual accept. Default [] = the group is not managed."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.auto_accept_projects : can(regex("^([0-9]{1,20}|[a-z][a-z0-9-]{4,28}[a-z0-9])$", p))])
    error_message = "auto_accept_projects entries must be project numbers or project IDs."
  }
}
