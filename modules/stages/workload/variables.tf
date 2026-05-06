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
  description = "The Organization ID"
  type        = string
}

variable "folder_id" {
  description = "The Folder ID to create the project in"
  type        = string
}

variable "billing_account" {
  description = "The Billing Account ID"
  type        = string
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
  description = "List of subnets in the Host Project to grant access to"
  type = map(object({
    region      = string
    subnet_name = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# IAM CONFIGURATION
# -----------------------------------------------------------------------------

variable "project_admin_group_email" {
  description = "Email of the Google Group to grant admin access"
  type        = string
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
}
