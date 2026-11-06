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

variable "permissions_boundary_arn" {
  description = "Permissions-boundary managed policy ARN set on every IAM role this module creates (a role's own roles[*].permissions_boundary takes precedence). Required when the roles are created by a member-account tfc-apply role with boundary propagation on (tfc-oidc-baseline enable_apply_boundary_propagation): pass arn:PARTITION:iam::ACCOUNT_ID:policy/tfc-apply-boundary. Null (default) = no boundary."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:[^:]+:iam::[^:]*:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be null or an IAM managed policy ARN (arn:PARTITION:iam::ACCOUNT_ID:policy/NAME)."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
