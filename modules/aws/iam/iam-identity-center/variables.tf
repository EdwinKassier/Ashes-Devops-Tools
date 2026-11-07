# -----------------------------------------------------------------------------
# Permission sets
# -----------------------------------------------------------------------------

variable "permission_sets" {
  description = "Map of permission set name to its definition. session_duration is an ISO-8601 duration (e.g. PT1H). managed_policy_names are AWS-managed policy names (the ARN is built for the running partition: aws, aws-us-gov or aws-cn) and managed_policy_arns are full policy ARNs (AWS-managed written out); customer_managed_policies reference policies by name and path that already exist in the target accounts; all three attach to the set; inline_policy is an optional inline IAM policy JSON document."
  type = map(object({
    description         = string
    session_duration    = string
    managed_policy_arns = optional(list(string), [])
    # AWS-managed policy names (e.g. "ReadOnlyAccess"); the ARN is built for the running partition.
    managed_policy_names = optional(list(string), [])
    inline_policy        = optional(string, "")
    # Customer-managed policies (must already exist in every target account); path defaults to "/".
    customer_managed_policies = optional(list(object({
      name = string
      path = optional(string, "/")
    })), [])
  }))
  default = {
    AdministratorAccess = {
      description          = "Full administrative access. Assign only to break-glass groups."
      session_duration     = "PT1H"
      managed_policy_names = ["AdministratorAccess"]
    }
    ReadOnly = {
      description          = "Organization-wide read-only access for auditors and viewers."
      session_duration     = "PT1H"
      managed_policy_names = ["ReadOnlyAccess"]
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
  description = "Map of assignment key to an assignment binding a permission set to a principal in a target AWS account. permission_set must be a key in permission_sets. Principal: set exactly one of principal_id (Identity Store group or user ID) or group_display_name (looked up in the Identity Store by DisplayName; implies a GROUP). Account: set exactly one of account_id or account_key (resolved through account_ids). Prefer GROUP principals; reserve USER for the management account only."
  type = map(object({
    permission_set     = string
    principal_type     = optional(string, "GROUP") # one of: GROUP, USER
    principal_id       = optional(string)          # Identity Store group or user ID
    group_display_name = optional(string)          # Identity Store group DisplayName
    account_id         = optional(string)          # Target AWS account ID
    account_key        = optional(string)          # Key into account_ids
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.assignments) : contains(["GROUP", "USER"], a.principal_type)
    ])
    error_message = "Each assignment principal_type must be either GROUP or USER."
  }

  validation {
    condition = alltrue([
      for a in values(var.assignments) :
      (a.principal_id != null) != (a.group_display_name != null) &&
      (a.group_display_name == null || a.principal_type == "GROUP")
    ])
    error_message = "Each assignment must set exactly one of principal_id or group_display_name (and group_display_name implies principal_type GROUP)."
  }

  validation {
    condition = alltrue([
      for a in values(var.assignments) : (a.account_id != null) != (a.account_key != null)
    ])
    error_message = "Each assignment must set exactly one of account_id or account_key."
  }

  validation {
    condition = alltrue([
      for a in values(var.assignments) : a.account_key == null || contains(keys(var.account_ids), coalesce(a.account_key, "-"))
    ])
    error_message = "An assignment account_key is not a key of account_ids (known keys are the account_ids map keys)."
  }
}

variable "account_ids" {
  description = "Map of account key (e.g. shared_services) to 12-digit AWS account ID, used to resolve assignments that set account_key."
  type        = map(string)
  default     = {}
  nullable    = false
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

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
