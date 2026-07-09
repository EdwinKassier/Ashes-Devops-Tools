# -----------------------------------------------------------------------------
# Account identity
# -----------------------------------------------------------------------------

variable "account_name" {
  description = "Human-readable name of the member account (e.g. \"log-archive\")."
  type        = string

  validation {
    condition     = length(trimspace(var.account_name)) > 0
    error_message = "account_name must be a non-empty string."
  }
}

variable "email" {
  description = "Root email address for the member account. Must be unique across all AWS accounts."
  type        = string

  validation {
    # Simple RFC-ish check: one @, non-empty local/domain parts, a dotted domain.
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email))
    error_message = "email must be a valid email address."
  }
}

variable "parent_ou_id" {
  description = "ID of the organizational unit (or root) the account is placed under."
  type        = string
}

# -----------------------------------------------------------------------------
# Account configuration
# -----------------------------------------------------------------------------

variable "cross_account_role_name" {
  description = "Name of the IAM role automatically created in the member account for cross-account access from the management account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "close_on_deletion" {
  description = "Whether to close the AWS account when the resource is destroyed (instead of only removing it from the organization)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the account. Merged with the module-managed managed-by=terraform tag."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Alternate contacts
# -----------------------------------------------------------------------------

variable "alternate_contacts" {
  description = "Alternate contacts to register on the account, keyed by an arbitrary label. contact_type must be one of SECURITY, BILLING, or OPERATIONS."
  type = map(object({
    contact_type  = string # SECURITY | BILLING | OPERATIONS
    name          = string
    title         = string
    email_address = string
    phone_number  = string
  }))
  default = {}

  validation {
    condition     = alltrue([for v in values(var.alternate_contacts) : contains(["SECURITY", "BILLING", "OPERATIONS"], v.contact_type)])
    error_message = "Each alternate_contacts entry must have contact_type set to one of SECURITY, BILLING, or OPERATIONS."
  }
}
