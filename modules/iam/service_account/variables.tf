variable "project_id" {
  description = "The ID of the project where the service account will be created"
  type        = string
}

variable "account_id" {
  description = "The service account ID (the part before @project.iam.gserviceaccount.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.account_id))
    error_message = "Account ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "display_name" {
  description = "The display name for the service account"
  type        = string
}

variable "description" {
  description = "A description of the service account"
  type        = string
  default     = ""
}

variable "project_roles" {
  description = "List of IAM roles to grant to the service account at project level"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for role in var.project_roles :
      can(regex("^roles/", role)) || can(regex("^projects/[^/]+/roles/", role))
    ])
    error_message = "Each role must be a valid GCP role (e.g., 'roles/storage.admin' or 'projects/my-project/roles/customRole')."
  }
}

variable "folder_roles" {
  description = "List of folder-level IAM role assignments"
  type = list(object({
    folder_id = string
    role      = string
  }))
  default = []
}

variable "organization_roles" {
  description = "List of organization-level IAM role assignments"
  type = list(object({
    org_id = string
    role   = string
  }))
  default = []
}

variable "impersonation_members" {
  description = "List of members allowed to impersonate this service account (format: user:email, group:email, serviceAccount:email)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.impersonation_members :
      can(regex("^(user:|group:|serviceAccount:)", m))
    ])
    error_message = "Each member must be prefixed with 'user:', 'group:', or 'serviceAccount:'."
  }
}

variable "workload_identity_members" {
  description = "List of members allowed to use this service account via Workload Identity (format: principalSet://... or serviceAccount:...)"
  type        = list(string)
  default     = []
}
