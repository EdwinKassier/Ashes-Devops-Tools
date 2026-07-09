# -----------------------------------------------------------------------------
# Generic workload / cross-account roles
# -----------------------------------------------------------------------------

variable "roles" {
  description = "Map of IAM role name to its configuration. trust_policy is a JSON assume-role policy document. managed_policy_arns are attached via separate attachment resources; inline_policy (JSON) is attached as a role inline policy when non-empty."
  type = map(object({
    trust_policy         = string
    max_session_duration = optional(number, 3600)
    managed_policy_arns  = optional(list(string), [])
    inline_policy        = optional(string, "")
    permissions_boundary = optional(string)
  }))
  default = {}

  validation {
    # Each trust_policy must be a parseable JSON document.
    condition     = alltrue([for k, v in var.roles : can(jsondecode(v.trust_policy))])
    error_message = "Each role's trust_policy must be a valid JSON document."
  }

  validation {
    # AWS constrains max_session_duration to 3600-43200 seconds (1-12 hours).
    condition     = alltrue([for k, v in var.roles : v.max_session_duration >= 3600 && v.max_session_duration <= 43200])
    error_message = "Each role's max_session_duration must be between 3600 and 43200 seconds."
  }
}

# -----------------------------------------------------------------------------
# Break-glass role
# -----------------------------------------------------------------------------

variable "enable_break_glass" {
  description = "Create the break-glass emergency-access role. Disabled-by-default: standing state is a deny-all inline policy."
  type        = bool
  default     = true
}

variable "break_glass_role_name" {
  description = "Name of the break-glass emergency-access role."
  type        = string
  default     = "break-glass"
}

variable "break_glass_trusted_principals" {
  description = "Account-qualified IAM principal ARNs allowed to assume the break-glass role (subject to the MFA conditions). Empty by default so no principal can assume it until explicitly configured."
  type        = list(string)
  default     = []

  validation {
    # Only enforce ARN shape on entries that are present; an empty list is valid.
    condition     = alltrue([for p in var.break_glass_trusted_principals : can(regex("^arn:aws:iam::[0-9]{12}:", p))])
    error_message = "Each break_glass_trusted_principals entry must be an account-qualified IAM ARN (arn:aws:iam::<12-digit-account>:...)."
  }
}

variable "break_glass_mfa_max_age" {
  description = "Maximum age in seconds of the MFA session (aws:MultiFactorAuthAge) permitted to assume the break-glass role."
  type        = number
  default     = 3600
}

variable "break_glass_active" {
  description = "Whether the break-glass role is activated for an incident. false (default) => deny-all standing policy; true => AdministratorAccess attached. Flip only during a declared incident."
  type        = bool
  default     = false
}
