/**
 * Copyright 2023 Ashes
 *
 * Host Module - Variables
 */

# =============================================================================
# CORE PROJECT CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "The GCP project ID (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC (e.g. \"10.0.0.0/16\"). Required — must be set explicitly to prevent accidental CIDR collisions when multiple VPCs exist. Use your IPAM or a per-environment tfvars file as the source of truth."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr_block))
    error_message = "vpc_cidr_block must be a valid CIDR notation (e.g. \"10.0.0.0/16\")."
  }
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr_block)) ? cidrhost(var.vpc_cidr_block, 0) == split("/", var.vpc_cidr_block)[0] : true
    error_message = "vpc_cidr_block must not have host bits set (e.g. use \"10.0.0.0/16\", not \"10.0.1.0/16\")."
  }
}

variable "project_prefix" {
  description = "Prefix for naming resources (e.g., 'ashes-dev'). Must start with a letter and contain only lowercase letters, digits, and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "The primary GCP region for resources (e.g., 'us-central1', 'europe-west1')"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region name (e.g., 'us-central1', 'europe-west1')."
  }
}

variable "explicit_zones" {
  description = <<-EOT
    Explicit list of zones to use for subnet layout (e.g. ["us-central1-a", "us-central1-b", "us-central1-c"]).

    ⚠️  PRODUCTION REQUIREMENT: always set this variable for any environment with live workloads.
    GCP occasionally changes how many zones the data source returns (e.g. 3 → 4 when a new
    zone is added to a region). Because subnet CIDRs are derived from zone count, a change will
    cause Terraform to plan subnet destruction and recreation — which evicts all running VMs.

    When empty, zones are auto-discovered via data.google_compute_zones (acceptable for dev/test
    environments where occasional disruption is tolerable).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for z in var.explicit_zones :
      can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", z))
    ])
    error_message = "Each entry in explicit_zones must be a valid GCP zone name (e.g. 'us-central1-a')."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

