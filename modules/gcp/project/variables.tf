# ─── Identity & placement ────────────────────────────────────────────────────

variable "project_id" {
  description = "Globally unique project ID, used verbatim (this module applies no prefix or suffix). 6-30 chars: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "name" {
  description = "Human-readable display name (4-30 chars). Defaults to project_id when null."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9 '\"!-]{4,30}$", var.name))
    error_message = "name must be 4-30 characters of letters, digits, spaces, hyphens, single/double quotes or exclamation marks."
  }
}

variable "parent" {
  description = "Parent resource the project is created under: \"folders/<numeric id>\" or \"organizations/<numeric id>\"."
  type        = string

  validation {
    condition     = can(regex("^(folders|organizations)/[0-9]+$", var.parent))
    error_message = "parent must be \"folders/<numeric id>\" or \"organizations/<numeric id>\"."
  }
}

variable "billing_account" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX) to link. Null leaves the project without billing (most APIs then cannot be enabled)."
  type        = string
  default     = null

  validation {
    condition     = var.billing_account == null || can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be null or a billing account ID in the format XXXXXX-XXXXXX-XXXXXX (uppercase alphanumeric)."
  }
}

variable "labels" {
  description = "Labels applied to the project (GCP label rules): keys start with a lowercase letter, then lowercase letters, digits, '_' or '-' (max 63); values use the same charset (max 63, may be empty). International lowercase characters are allowed. No uppercase or spaces."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^\\p{Ll}[\\p{Ll}\\p{Lo}\\p{N}_-]{0,62}$", k)) && can(regex("^[\\p{Ll}\\p{Lo}\\p{N}_-]{0,63}$", v))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, digits, '_' or '-' (max 63); values the same charset (max 63). No uppercase or spaces."
  }
}

variable "deletion_policy" {
  description = "Project deletion policy: PREVENT (default — a destroy plan fails), ABANDON (remove from state, keep the project) or DELETE."
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy must be one of PREVENT, ABANDON or DELETE."
  }
}

# ─── APIs ────────────────────────────────────────────────────────────────────

variable "services" {
  description = "APIs to enable on the project (e.g. \"compute.googleapis.com\"). Enabled with disable_on_destroy = false, so removing one from this list only stops managing it."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z][a-z0-9.-]*\\.googleapis\\.com$", s))])
    error_message = "Every service must be an API name ending in .googleapis.com (e.g. compute.googleapis.com)."
  }
}

# ─── Shared VPC ──────────────────────────────────────────────────────────────

variable "shared_vpc_host_project_id" {
  description = "When set, attach this project as a Shared VPC service project of the given host project. The host must already be a Shared VPC host and compute.googleapis.com must be in var.services. Null = no attachment."
  type        = string
  default     = null

  validation {
    condition     = var.shared_vpc_host_project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.shared_vpc_host_project_id))
    error_message = "shared_vpc_host_project_id must be null or a valid project ID."
  }

  validation {
    condition     = var.shared_vpc_host_project_id == null || contains(var.services, "compute.googleapis.com")
    error_message = "A Shared VPC service-project attachment requires compute.googleapis.com in var.services."
  }
}

# ─── IAM ─────────────────────────────────────────────────────────────────────

variable "iam" {
  description = "Additive project IAM: map of role => set of members (\"user:\", \"group:\", \"serviceAccount:\", \"domain:\", \"principal:\" or \"principalSet:\"). Uses google_project_iam_member, so bindings managed elsewhere are never evicted."
  type        = map(set(string))
  default     = {}

  validation {
    condition = alltrue([
      for role in keys(var.iam) :
      can(regex("^(roles|projects/[^/]+/roles|organizations/[0-9]+/roles)/[a-zA-Z0-9._]+$", role))
    ])
    error_message = "IAM roles must be 'roles/<name>', 'projects/<id>/roles/<name>' or 'organizations/<num>/roles/<name>'."
  }

  validation {
    condition = alltrue(flatten([
      for role, members in var.iam : [
        for m in members : can(regex("^(user|group|serviceAccount|domain|principal|principalSet):.+$", m))
      ]
    ]))
    error_message = "IAM members must be prefixed with user:, group:, serviceAccount:, domain:, principal: or principalSet:."
  }
}

# ─── Essential Contacts ──────────────────────────────────────────────────────

variable "essential_contacts" {
  description = "Essential Contacts: map of email => list of notification categories (ALL, SUSPENSION, SECURITY, TECHNICAL, BILLING, LEGAL, PRODUCT_UPDATES, TECHNICAL_INCIDENTS). Requires essentialcontacts.googleapis.com on the project (or the org-level contacts API)."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for email in keys(var.essential_contacts) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email))])
    error_message = "essential_contacts keys must be valid email addresses."
  }

  validation {
    condition = alltrue(flatten([
      for email, cats in var.essential_contacts : [
        for c in cats : contains(["ALL", "SUSPENSION", "SECURITY", "TECHNICAL", "BILLING", "LEGAL", "PRODUCT_UPDATES", "TECHNICAL_INCIDENTS"], c)
      ]
    ])) && alltrue([for email, cats in var.essential_contacts : length(cats) > 0])
    error_message = "Each essential contact needs at least one category from ALL, SUSPENSION, SECURITY, TECHNICAL, BILLING, LEGAL, PRODUCT_UPDATES, TECHNICAL_INCIDENTS."
  }
}

variable "essential_contacts_language" {
  description = "Language tag (BCP-47) for Essential Contacts notifications."
  type        = string
  default     = "en"

  validation {
    condition     = can(regex("^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$", var.essential_contacts_language))
    error_message = "essential_contacts_language must be a BCP-47 language tag such as \"en\" or \"en-GB\"."
  }
}

# ─── Lien ────────────────────────────────────────────────────────────────────

variable "lien_reason" {
  description = "When set, place a resourcemanager.projects.delete lien on the project with this reason (a second, API-level guard on top of deletion_policy). Null = no lien."
  type        = string
  default     = null

  validation {
    condition     = var.lien_reason == null || try(length(trimspace(var.lien_reason)) > 0, false)
    error_message = "lien_reason must be null or a non-empty string."
  }
}

# ─── Tags ────────────────────────────────────────────────────────────────────

variable "tag_bindings" {
  description = "Resource-manager tag bindings: map of arbitrary static key => tag value ID (\"tagValues/<numeric id>\"). Keys must be known at plan time."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.tag_bindings) : can(regex("^tagValues/[0-9]+$", v))])
    error_message = "tag_bindings values must be tag value IDs in the form tagValues/<numeric id>."
  }
}
