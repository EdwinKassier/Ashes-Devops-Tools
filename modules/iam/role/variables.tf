variable "level" {
  description = "Level at which to create the custom role: 'project' or 'organization'"
  type        = string
  default     = "project"

  validation {
    condition     = contains(["project", "organization"], var.level)
    error_message = "Level must be 'project' or 'organization'."
  }
}

variable "project_id" {
  description = "The ID of the project where the custom role will be created (required when level is 'project')"
  type        = string
  default     = null
}

variable "org_id" {
  description = "The organization ID where the custom role will be created (required when level is 'organization')"
  type        = string
  default     = null
}

variable "role_id" {
  description = "The camelCaseRoleId for the custom role (e.g., 'myCustomRole')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_\\.]{2,63}$", var.role_id))
    error_message = "Role ID must be 3-64 characters, start with a letter, and contain only letters, numbers, underscores, and periods."
  }
}

variable "title" {
  description = "A human-readable title for the custom role"
  type        = string
}

variable "description" {
  description = "A description of the custom role"
  type        = string
  default     = ""
}

variable "permissions" {
  description = "The list of permissions that the custom role will grant"
  type        = list(string)

  validation {
    condition     = length(var.permissions) > 0
    error_message = "At least one permission must be specified."
  }

  validation {
    condition = alltrue([
      for p in var.permissions :
      can(regex("^[a-zA-Z]+\\.[a-zA-Z]+\\.[a-zA-Z]+$", p))
    ])
    error_message = "Each permission must be in format 'service.resource.action' (e.g., 'storage.objects.get')."
  }
}

variable "stage" {
  description = "The current launch stage of the role (ALPHA, BETA, GA, DEPRECATED, DISABLED, EAP)"
  type        = string
  default     = "GA"

  validation {
    condition     = contains(["ALPHA", "BETA", "GA", "DEPRECATED", "DISABLED", "EAP"], var.stage)
    error_message = "Stage must be one of: ALPHA, BETA, GA, DEPRECATED, DISABLED, EAP."
  }
}