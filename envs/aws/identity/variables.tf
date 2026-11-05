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

# -----------------------------------------------------------------------------
# Tagging — provider default_tags (FinOps / governance)
#
# Every resource the aws provider(s) in this root create gets the canonical tag
# set: CostCenter / Environment / Owner (the keys the tag policy enforces and
# cost-governance activates as cost-allocation tags) plus ManagedBy /
# LandingZone / Workspace. default_tags is merged LAST, so it can add keys or
# override any canonical value.
# -----------------------------------------------------------------------------

variable "landing_zone_name" {
  description = "Landing-zone identifier written to the LandingZone tag on every resource."
  type        = string
  default     = "ashes"

  validation {
    condition     = length(trimspace(var.landing_zone_name)) > 0
    error_message = "landing_zone_name must be a non-empty string."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root."
  type        = string
  default     = "platform"

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list)."
  type        = string
  default     = "platform-team"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "default_tags" {
  description = "Extra tags merged into the aws provider default_tags (after the canonical set, so they may override it). Values must be non-empty."
  type        = map(string)
  default     = {}

  validation {
    # An empty-string default tag makes the provider plan a perpetual diff.
    condition     = alltrue([for v in values(var.default_tags) : length(trimspace(v)) > 0])
    error_message = "default_tags values must be non-empty strings."
  }
}

# -----------------------------------------------------------------------------
# Credentials
# -----------------------------------------------------------------------------

variable "assume_role_arn" {
  description = "Optional role the aws provider(s) assume. Default null: the workspace's TFC dynamic credentials (TFC_AWS_PROVIDER_AUTH + TFC_AWS_PLAN_ROLE_ARN / TFC_AWS_APPLY_ROLE_ARN, from the aws-organization outputs tfc_plan_role_arns / tfc_apply_role_arns) already resolve to the target member account, so no hop is made. Legacy / local runs from management-account credentials set this to the account's account_role_arns entry (OrganizationAccountAccessRole)."
  type        = string
  default     = null

  validation {
    condition     = var.assume_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.assume_role_arn, "x")))
    error_message = "assume_role_arn must be null or an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}
