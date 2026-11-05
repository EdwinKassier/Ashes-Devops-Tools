/**
 * Copyright 2023 Ashes
 *
 * Workload Factory Module - Variables
 */

variable "project_name" {
  description = "Display name of the project, also the project-ID stem: the project ID is \"<project_name>-<4 hex>\". 4-25 chars, lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 4-25 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen (the 5-char \"-<hex>\" suffix keeps the project ID within 30)."
  }
}

variable "org_id" {
  description = "The numeric GCP Organization ID (digits only, without 'organizations/' prefix). Used as the parent only when folder_id is null."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "folder_id" {
  description = "The numeric Folder ID to create the project in (digits only, without 'folders/' prefix). When null the project is created directly under org_id."
  type        = string
  default     = null

  validation {
    condition     = var.folder_id == null || can(regex("^[0-9]+$", var.folder_id))
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
  description = "Additional APIs to enable in the project. compute.googleapis.com and servicenetworking.googleapis.com are always enabled; container.googleapis.com only when enable_gke (or enable_gke_network_user) is true."
  type        = list(string)
  default     = []
}

variable "enable_gke" {
  description = "Enable container.googleapis.com (GKE) on the project. Previously force-enabled on every workload project by the upstream project-factory call; now opt-in. Implied by enable_gke_network_user."
  type        = bool
  default     = false
}

variable "create_project_service_account" {
  description = "Create the dedicated \"project-service-account\" SA in the project (and grant it compute.networkUser on the Shared VPC subnets). Matches the upstream project-factory default (create_project_sa = true)."
  type        = bool
  default     = true
}

variable "default_service_account_action" {
  description = "What to do with the project's default compute service account: DISABLE (default, matches the upstream project-factory), DEPRIVILEGE, DELETE or KEEP (leave it untouched)."
  type        = string
  default     = "DISABLE"

  validation {
    condition     = contains(["DISABLE", "DEPRIVILEGE", "DELETE", "KEEP"], var.default_service_account_action)
    error_message = "default_service_account_action must be one of DISABLE, DEPRIVILEGE, DELETE or KEEP."
  }
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

  validation {
    condition     = !var.enable_shared_vpc_attachment || var.shared_vpc_host_project_id != ""
    error_message = "shared_vpc_host_project_id is required when enable_shared_vpc_attachment is true."
  }
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

variable "enable_gke_network_user" {
  description = <<-EOT
    When true, also grants the GKE robot service account
    (service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com)
    the roles/compute.networkUser role on the shared VPC subnets. Set to true
    only when this service project will use GKE — the GKE robot SA is created
    lazily when container.googleapis.com is first activated, so enabling this
    flag before GKE is enabled creates a dangling IAM binding that Terraform
    will attempt to reconcile on every apply.
  EOT
  type        = bool
  default     = false
}

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
    List of roles to grant to the admin group at project level.

    Bindings are managed via google_project_iam_member (additive). Manually-granted
    bindings or bindings managed by other tools are preserved on every apply — this
    module will not evict them.

    Validation blocks reject primitive roles (owner/editor/viewer) and
    cross-boundary privileged roles (organizationAdmin, folderAdmin, securityAdmin,
    organizationRoleAdmin, billing.admin, billing.creator). Use least-privilege
    predefined or custom roles only.
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
