/**
 * Copyright 2023 Ashes
 *
 * Shared VPC Service Project Module - Variables
 */

# -----------------------------------------------------------------------------
# REQUIRED VARIABLES
# -----------------------------------------------------------------------------

variable "host_project_id" {
  description = "The ID of the Shared VPC Host Project"
  type        = string
}

variable "service_project_id" {
  description = "The ID of the Service Project to attach"
  type        = string
}

# -----------------------------------------------------------------------------
# SERVICE PROJECT CONFIGURATION
# -----------------------------------------------------------------------------

variable "deletion_policy" {
  description = "The deletion policy for the shared VPC link. ABANDON to leave resources, DELETE to destroy them."
  type        = string
  default     = "ABANDON"

  validation {
    condition     = contains(["ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy must be either 'ABANDON' or 'DELETE'."
  }
}

# -----------------------------------------------------------------------------
# SUBNET-LEVEL IAM
# -----------------------------------------------------------------------------

variable "subnet_iam_bindings" {
  description = "List of subnet-level IAM bindings for compute.networkUser role"
  type = list(object({
    subnet = string
    region = string
    member = string
  }))
  default = []
}

# -----------------------------------------------------------------------------
# PROJECT-LEVEL IAM
# -----------------------------------------------------------------------------

variable "grant_network_user_to_all_subnets" {
  description = "Whether to grant compute.networkUser at project level (access to all subnets)"
  type        = bool
  default     = false
}

variable "network_user_members" {
  description = "List of members to grant compute.networkUser role (when grant_network_user_to_all_subnets is true)"
  type        = list(string)
  default     = []
}

variable "network_viewer_members" {
  description = "List of members to grant compute.networkViewer role (read-only network access)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# GKE CONFIGURATION
# -----------------------------------------------------------------------------

variable "enable_gke_permissions" {
  description = "Whether to grant GKE service account permissions on host project"
  type        = bool
  default     = false
}
