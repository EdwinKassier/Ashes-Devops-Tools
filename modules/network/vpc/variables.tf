/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Variables
 */

variable "project_id" {
  description = "The ID of the project where this VPC will be created"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "main-vpc"
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,62}$", var.vpc_name))
    error_message = "vpc_name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens (max 63 characters)."
  }
}

variable "routing_mode" {
  description = "The network routing mode (default 'GLOBAL')"
  type        = string
  default     = "GLOBAL"
  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "Routing mode must be either 'REGIONAL' or 'GLOBAL'."
  }
}

variable "description" {
  description = "An optional description of this resource"
  type        = string
  default     = "Managed by Terraform"
}

variable "delete_default_routes_on_create" {
  description = "If set to true, default routes (0.0.0.0/0) will be deleted immediately after network creation"
  type        = bool
  default     = true
}

variable "auto_create_subnetworks" {
  description = "When set to true, the network is created in 'auto subnet mode' and it will create a subnet for each region automatically"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# SHARED VPC (Enterprise)
# -----------------------------------------------------------------------------

variable "enable_shared_vpc_host" {
  description = "Enable this project as a Shared VPC Host Project"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# DELETION PROTECTION
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = <<-EOT
    Prevent accidental destruction of the VPC network.

    When true, a terraform_data guard resource is created with prevent_destroy = true.
    Terraform refuses to destroy this module while the guard exists. To intentionally
    remove a protected VPC, first run:
      terraform state rm 'module.<name>.terraform_data.deletion_protection_guard'
  EOT
  type        = bool
  default     = false
}