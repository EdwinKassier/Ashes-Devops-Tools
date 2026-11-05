/**
 * Copyright 2023 Ashes
 *
 * GKE Autopilot Module - Variables
 */

variable "project_id" {
  description = "The ID of the project where the cluster will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "name" {
  description = "Name of the GKE Autopilot cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,38}[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens (max 40 characters)."
  }
}

variable "location" {
  description = "The GCP region to host the regional Autopilot cluster in (e.g. europe-west1). Autopilot clusters are always regional."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.location))
    error_message = "location must be a valid GCP region (e.g. \"europe-west1\")."
  }
}

variable "network" {
  description = "The self_link or name of the Shared VPC network to attach the cluster to"
  type        = string
}

variable "subnetwork" {
  description = "The self_link or name of the Shared VPC subnetwork to attach the cluster nodes to"
  type        = string
}

# -----------------------------------------------------------------------------
# IP ALLOCATION (VPC-native / alias IP)
# -----------------------------------------------------------------------------

variable "cluster_secondary_range_name" {
  description = "Name of the subnetwork secondary range to use for pod IPs. Leave null to let GKE allocate a range automatically."
  type        = string
  default     = null
}

variable "services_secondary_range_name" {
  description = "Name of the subnetwork secondary range to use for service (ClusterIP) IPs. Leave null to let GKE allocate a range automatically."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# RELEASE CHANNEL
# -----------------------------------------------------------------------------

variable "release_channel" {
  description = "The GKE release channel the cluster subscribes to for automatic version upgrades"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of 'RAPID', 'REGULAR', or 'STABLE'."
  }
}

# -----------------------------------------------------------------------------
# PRIVATE CLUSTER (secure by default)
# -----------------------------------------------------------------------------

variable "enable_private_endpoint" {
  description = "When true, the cluster's control-plane endpoint has no public IP and is reachable only from within the VPC. Nodes are always private."
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "The /28 CIDR range for the hosted control-plane (master) network. Must not overlap any other range in the VPC."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "master_ipv4_cidr_block must be a valid CIDR block (e.g. \"172.16.0.0/28\")."
  }
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks allowed to reach the control-plane endpoint. Required (non-empty) when enable_private_endpoint = false so a public endpoint is never left open to the internet."
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []

  validation {
    condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
    error_message = "master_authorized_networks must contain at least one CIDR block when enable_private_endpoint = false."
  }
}

# -----------------------------------------------------------------------------
# DELETION PROTECTION
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = <<-EOT
    Prevent accidental destruction of the cluster.

    When true, the cluster's own deletion_protection API attribute is set and a
    terraform_data guard resource is created with prevent_destroy = true, so
    Terraform refuses to destroy this module. To intentionally remove a protected
    cluster, set this to false (which also removes the guard) and apply, or run:
      terraform state rm 'module.<name>.terraform_data.deletion_protection_guard'
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# LABELS
# -----------------------------------------------------------------------------

variable "resource_labels" {
  description = "A map of key/value labels to apply to the cluster"
  type        = map(string)
  default     = {}
}
