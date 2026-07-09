# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the default provider assumes the shared-services account role in. Identity Center is a global service; this region only scopes the API calls."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

# -----------------------------------------------------------------------------
# Identity Center permission sets + assignments (passed to the module)
# -----------------------------------------------------------------------------

variable "permission_sets" {
  description = "Map of permission set name to definition, passed to the iam-identity-center module. Defaults to a small AdministratorAccess + ReadOnly set; override to add finer-grained sets."
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
}

variable "assignments" {
  description = "Map of assignment key to a binding of a permission set to a principal (GROUP or USER) in a target AWS account. account_id may be set directly or, in tfvars, resolved from the org remote state via the account_ids map."
  type = map(object({
    permission_set = string
    principal_type = string
    principal_id   = string
    account_id     = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Attribute-based access control (ABAC)
# -----------------------------------------------------------------------------

variable "enable_abac" {
  description = "Whether to enable attribute-based access control on the Identity Center instance."
  type        = bool
  default     = false
}

variable "abac_attributes" {
  description = "Map of ABAC attribute key to the list of attribute sources that populate it. Only used when enable_abac is true."
  type        = map(list(string))
  default     = {}
}
