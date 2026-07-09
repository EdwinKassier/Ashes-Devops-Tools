# -----------------------------------------------------------------------------
# Permission sets
# -----------------------------------------------------------------------------

variable "permission_sets" {
  description = "Map of permission set name to its definition. session_duration is an ISO-8601 duration (e.g. PT1H). managed_policy_arns are AWS-managed policy ARNs attached to the set; inline_policy is an optional inline IAM policy JSON document."
  type = map(object({
    description         = string
    session_duration    = string
    managed_policy_arns = optional(list(string), [])
    inline_policy       = optional(string, "")
  }))
  default = {
    AdministratorAccess = {
      description         = "Full administrative access. Assign only to break-glass groups."
      session_duration    = "PT1H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    ReadOnly = {
      description         = "Organization-wide read-only access for auditors and viewers."
      session_duration    = "PT1H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }

  validation {
    # ISO-8601 hour duration, PT1H..PT12H. Interval is tiny (<=1000) per the
    # regex-interval constraint; the alternation caps the value at 12 hours,
    # which is the AWS Identity Center maximum session duration.
    condition = alltrue([
      for ps in values(var.permission_sets) : can(regex("^PT([0-9]|1[0-2])H$", ps.session_duration))
    ])
    error_message = "Each permission set session_duration must be an ISO-8601 hour duration between PT1H and PT12H (e.g. PT1H, PT8H, PT12H)."
  }
}

# -----------------------------------------------------------------------------
# Account assignments
# -----------------------------------------------------------------------------

variable "assignments" {
  description = "Map of assignment key to an assignment binding a permission set to a principal (GROUP or USER) in a target AWS account. permission_set must be a key in permission_sets. Prefer GROUP principals; reserve USER for the management account only."
  type = map(object({
    permission_set = string
    principal_type = string # one of: GROUP, USER
    principal_id   = string # Identity Store group or user ID
    account_id     = string # Target AWS account ID
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.assignments) : contains(["GROUP", "USER"], a.principal_type)
    ])
    error_message = "Each assignment principal_type must be either GROUP or USER."
  }
}

# -----------------------------------------------------------------------------
# Attribute-based access control (ABAC)
# -----------------------------------------------------------------------------

variable "enable_abac" {
  description = "Whether to enable attribute-based access control on the Identity Center instance, allowing session/IdP attributes to be referenced in permission-set policies via aws:PrincipalTag."
  type        = bool
  default     = false
}

variable "abac_attributes" {
  description = "Map of ABAC attribute key to the list of attribute sources (identity-store or IdP attribute paths) that populate it. Only used when enable_abac is true."
  type        = map(list(string))
  default     = {}
}
