# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via the TF_CLOUD_ORGANIZATION environment variable (kept out of the code so the same root works across orgs and CI). Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

variable "organization_contract" {
  description = "aws-organization stage contract (FAST-style override), the same type in every aws root: organization_id (o-xxxxxxxxxx), organization_root_id (r-xxxx), management_account_id, ou_ids (OU name => OU ID), account_ids (account key => 12-digit ID), account_role_arns (account key => cross-account role ARN). This root needs: account_ids. When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else the contract output of the organization_workspace_name workspace."
  type = object({
    organization_id       = optional(string)
    organization_root_id  = optional(string)
    management_account_id = optional(string)
    ou_ids                = optional(map(string), {})
    account_ids           = map(string)
    account_role_arns     = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.organization_contract == null || alltrue([for id in values(try(var.organization_contract.account_ids, {})) : can(regex("^[0-9]{12}$", id))])
    error_message = "organization_contract.account_ids values must be 12-digit AWS account IDs."
  }
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the default provider assumes the shared-services account role in. Identity Center is a global service; this region only scopes the API calls. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (or org.regions.aws in config/landing-zone.yaml) must be a valid AWS region name, e.g. eu-west-2."
  }
}

# -----------------------------------------------------------------------------
# Identity Center permission sets + assignments (passed to the module)
# -----------------------------------------------------------------------------

variable "permission_sets" {
  description = "Map of permission set name to definition, passed to the iam-identity-center module. Defaults: AdministratorAccess (break-glass), PlatformAdmin, Developer (PowerUserAccess), SecurityAudit and ReadOnly; override to add finer-grained sets."
  type = map(object({
    description         = string
    session_duration    = string
    managed_policy_arns = optional(list(string), [])
    # AWS-managed policy names (e.g. "ReadOnlyAccess"); the ARN is built for the running partition.
    managed_policy_names = optional(list(string), [])
    inline_policy        = optional(string, "")
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
    PlatformAdmin = {
      description          = "Platform engineering administrative access (AdministratorAccess, time-boxed)."
      session_duration     = "PT4H"
      managed_policy_names = ["AdministratorAccess"]
    }
    Developer = {
      description          = "Application developer access: everything except IAM and Organizations administration (PowerUserAccess)."
      session_duration     = "PT8H"
      managed_policy_names = ["PowerUserAccess"]
    }
    SecurityAudit = {
      description          = "Read-only security audit access (SecurityAudit)."
      session_duration     = "PT4H"
      managed_policy_names = ["SecurityAudit"]
    }
    ReadOnly = {
      description          = "Organization-wide read-only access for auditors and viewers."
      session_duration     = "PT1H"
      managed_policy_names = ["ReadOnlyAccess"]
    }
  }
}

variable "assignments" {
  description = "Explicit assignments (merged with those derived from aws.identity.groups): map of assignment key to a binding of a permission set to a principal in a target account. Set exactly one of principal_id / group_display_name and exactly one of account_id / account_key (a key of the org contract account_ids)."
  type = map(object({
    permission_set     = string
    principal_type     = optional(string, "GROUP")
    principal_id       = optional(string)
    group_display_name = optional(string)
    account_id         = optional(string)
    account_key        = optional(string)
  }))
  default = {}
}

variable "identity_groups" {
  description = "Name-based assignments: Identity Store group display name => list of {permission_set, accounts} where accounts are keys of the org contract account_ids. Null = aws.identity.groups from config/landing-zone.yaml (absent = none)."
  type = map(list(object({
    permission_set = string
    accounts       = list(string)
  })))
  default = null

  validation {
    condition = alltrue(flatten([
      for g, entries in coalesce(var.identity_groups, local.cfg.identity_groups, {}) : [
        for e in entries : [
          for a in e.accounts : contains(keys(local.org.account_ids), a)
        ]
      ]
    ]))
    error_message = "identity groups (var.identity_groups or aws.identity.groups) name an account key that is not in the organization contract account_ids."
  }

  validation {
    condition = alltrue(flatten([
      for g, entries in coalesce(var.identity_groups, local.cfg.identity_groups, {}) : [
        for e in entries : contains(keys(var.permission_sets), e.permission_set)
      ]
    ]))
    error_message = "identity groups (var.identity_groups or aws.identity.groups) name a permission_set that is not in permission_sets."
  }
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
  description = "Landing-zone identifier written to the LandingZone tag on every resource. Null = org.name from config/landing-zone.yaml (the single source shared by every AWS root). The upstream placeholders \"ashes\" and \"my-org\" are rejected."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is unset or invalid: set var.landing_zone_name or org.name in config/landing-zone.yaml. It must be 2-31 chars: a lowercase letter, then lowercase letters, digits or hyphens."
  }

  validation {
    condition     = !contains(["ashes", "my-org"], lower(coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is still an upstream placeholder (ashes / my-org). Set your own landing-zone identifier."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root. Null = org.cost_center from config/landing-zone.yaml, else \"platform\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform"))) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list). Null = org.owner from config/landing-zone.yaml, else \"platform-team\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team"))) > 0
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
