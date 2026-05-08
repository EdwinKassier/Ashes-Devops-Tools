/**
 * Copyright 2023 Ashes
 *
 * Workload Factory Module - Variables
 */

variable "project_name" {
  description = "The name of the project to create"
  type        = string
}

variable "org_id" {
  description = "The numeric GCP Organization ID (digits only, without 'organizations/' prefix)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "folder_id" {
  description = "The numeric Folder ID to create the project in (digits only, without 'folders/' prefix)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.folder_id))
    error_message = "folder_id must be a numeric folder ID (digits only, without 'folders/' prefix)."
  }
}

variable "billing_account" {
  description = "The GCP Billing Account ID in format XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "activate_apis" {
  description = "List of APIs to enable in the project"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the project"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# SHARED VPC CONFIGURATION
# -----------------------------------------------------------------------------

variable "enable_shared_vpc_attachment" {
  description = "Whether to attach this project to a Shared VPC Host"
  type        = bool
  default     = true
}

variable "shared_vpc_host_project_id" {
  description = "The Host Project ID for Shared VPC"
  type        = string
  default     = ""
}

variable "shared_vpc_subnets" {
  description = "Map of subnet key to subnet configuration in the Shared VPC Host Project. Must not be empty when enable_shared_vpc_attachment is true — at least one subnet must be granted to allow workloads to use the shared network."
  type = map(object({
    region      = string
    subnet_name = string
  }))
  default = {}

  validation {
    condition     = !var.enable_shared_vpc_attachment || length(var.shared_vpc_subnets) > 0
    error_message = "shared_vpc_subnets must contain at least one subnet when enable_shared_vpc_attachment is true."
  }
}

# -----------------------------------------------------------------------------
# IAM CONFIGURATION
# -----------------------------------------------------------------------------

variable "project_admin_group_email" {
  description = "Email of the Google Group to grant admin access"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.project_admin_group_email))
    error_message = "project_admin_group_email must be a valid email address."
  }
}

variable "project_admin_roles" {
  description = <<-EOT
    List of roles to grant to the admin group via google_project_iam_binding.

    WARNING: google_project_iam_binding is AUTHORITATIVE per role. On every apply it
    removes any other member that holds the role, including manually-granted access.
    Any member not in this list will lose the role on the next terraform apply.

    Consider using google_project_iam_member (additive) instead if you need to
    coexist with bindings managed outside of Terraform.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for role in var.project_admin_roles :
      can(regex("^(roles|projects/[^/]+/roles|organizations/[0-9]+/roles)/[a-zA-Z0-9._]+$", role))
    ])
    error_message = "All roles must be valid GCP role strings: 'roles/<name>', 'projects/<id>/roles/<name>', or 'organizations/<num>/roles/<name>'."
  }

  validation {
    condition = alltrue([
      for role in var.project_admin_roles :
      !contains(["roles/owner", "roles/editor", "roles/viewer"], role)
    ])
    error_message = "project_admin_roles must not include basic roles. Grant only least-privilege predefined or custom roles."
  }

  validation {
    # Block cross-boundary privileged roles that must never be granted at project level.
    # These roles grant control over the entire org/folder hierarchy above the project
    # and would allow privilege escalation far beyond the intended project scope.
    condition = alltrue([
      for role in var.project_admin_roles :
      !contains([
        "roles/resourcemanager.organizationAdmin",
        "roles/resourcemanager.folderAdmin",
        "roles/iam.securityAdmin",
        "roles/iam.organizationRoleAdmin",
        "roles/billing.admin",
        "roles/billing.creator",
      ], role)
    ])
    error_message = "project_admin_roles must not include org/folder-level privileged roles (organizationAdmin, folderAdmin, securityAdmin, organizationRoleAdmin, billing.admin, billing.creator). These roles span beyond the project boundary."
  }
}
