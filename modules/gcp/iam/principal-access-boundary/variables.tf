variable "organization_id" {
  description = "Numeric organization ID that owns the principal access boundary policy."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id must be numeric (digits only, without organizations/)."
  }
}

variable "policy_id" {
  description = "ID of the principal access boundary policy (also the prefix of every binding ID)."
  type        = string
  default     = "automation-boundary"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.policy_id))
    error_message = "policy_id must be 3-42 lowercase letters, digits or hyphens, start with a letter and not end with a hyphen."
  }
}

variable "display_name" {
  description = "Display name of the policy (at most 63 characters)."
  type        = string
  default     = "Landing zone automation boundary"

  validation {
    condition     = length(var.display_name) <= 63
    error_message = "display_name must be at most 63 characters."
  }
}

variable "enforcement_version" {
  description = "Enforcement version: which permissions IAM enforces the boundary for. A pinned number keeps behaviour stable when Google adds coverage; \"latest\" follows it automatically."
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^([1-9][0-9]*|latest)$", var.enforcement_version))
    error_message = "enforcement_version must be a positive integer string or \"latest\"."
  }
}

variable "allowed_resources" {
  description = "Resource-hierarchy nodes the bound principals may act on (//cloudresourcemanager.googleapis.com/organizations/<id>, .../folders/<id> or .../projects/<id>). Empty = this organization only."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.allowed_resources : can(regex("^//cloudresourcemanager\\.googleapis\\.com/(organizations|folders|projects)/[a-z0-9-]+$", r))])
    error_message = "allowed_resources entries must be //cloudresourcemanager.googleapis.com/(organizations|folders|projects)/<id>."
  }

  validation {
    condition     = length(var.allowed_resources) <= 500
    error_message = "A principal access boundary rule holds at most 500 resources."
  }
}

variable "project_bindings" {
  description = "Map of short binding key => project ID. Every service account in each project is bound to the boundary (principal set //cloudresourcemanager.googleapis.com/projects/<id>)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, p in var.project_bindings : can(regex("^[a-z][a-z0-9-]{0,19}$", k)) && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", p))])
    error_message = "project_bindings keys must be 1-20 lowercase letters, digits or hyphens starting with a letter; values must be valid project IDs."
  }
}
