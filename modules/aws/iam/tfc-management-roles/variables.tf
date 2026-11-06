variable "tfc_organization" {
  description = "Terraform Cloud organization of the trusted workspaces (matched literally in the trust sub)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.tfc_organization))
    error_message = "tfc_organization must be a literal TFC organization name (no wildcards)."
  }
}

variable "tfc_project" {
  description = "Default TFC project of the trusted workspaces (matched literally in the trust sub). Override per workspace with workspaces[*].project."
  type        = string
  default     = "Default Project"
}

variable "tfc_hostname" {
  description = "HCP Terraform / TFE hostname issuing the workload-identity tokens."
  type        = string
  default     = "app.terraform.io"

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.tfc_hostname))
    error_message = "tfc_hostname must be a bare hostname such as app.terraform.io."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the management account's TFC OIDC provider (created in phase 0). Null derives arn:<partition>:iam::<this account>:oidc-provider/<tfc_hostname>."
  type        = string
  default     = null
}

variable "workspaces" {
  description = "Management-default workspaces that get their own plan/apply role pair, keyed by workspace name. aws-security and aws-backup have built-in least-privilege apply policies; any other workspace must set apply_policy_json. project overrides tfc_project for that workspace."
  type = map(object({
    project           = optional(string)
    apply_policy_json = optional(string)
  }))
  default = {
    "aws-security" = {}
    "aws-backup"   = {}
  }

  validation {
    condition     = alltrue([for ws, w in var.workspaces : contains(["aws-security", "aws-backup"], ws) || w.apply_policy_json != null])
    error_message = "Only aws-security and aws-backup have built-in apply policies; other workspaces must set apply_policy_json."
  }

  validation {
    condition     = !contains(keys(var.workspaces), "aws-organization")
    error_message = "aws-organization keeps the phase-0 management role; it must not be listed here."
  }
}

variable "role_name_prefix" {
  description = "Prefix of the role names (<prefix><workspace>-<phase>). Every role with this prefix is protected from modification by the roles themselves."
  type        = string
  default     = "tfc-mgmt-"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,30}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-30 IAM role-name characters."
  }
}

variable "member_pivot_role_names" {
  description = "Member-account role names the management roles must never assume (OrganizationAccountAccessRole and the member tfc-* roles by default)."
  type        = list(string)
  default     = ["OrganizationAccountAccessRole", "tfc-plan", "tfc-apply", "break-glass"]
  nullable    = false
}

variable "protected_role_names" {
  description = "Management-account role names, beyond <role_name_prefix>* (which already covers the phase-0 tfc-mgmt-plan / tfc-mgmt-apply roles), that no management role may modify. The break-glass role names are protected too: the aws-security management role may not create or edit the management break-glass role, which every member break-glass role trusts."
  type        = list(string)
  default     = ["OrganizationAccountAccessRole", "OrganizationBreakGlass", "break-glass"]
  nullable    = false
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (3600-43200)."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "tags" {
  description = "Tags applied to the roles."
  type        = map(string)
  default     = {}
}

variable "security_trail_role_pattern" {
  description = "Name pattern of the ONLY management-account role the aws-security apply role may create or modify: the organization trail's CloudWatch Logs delivery role (<trail_name>-cloudwatch-delivery)."
  type        = string
  default     = "*-cloudwatch-delivery"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_*-]{1,64}$", var.security_trail_role_pattern)) && var.security_trail_role_pattern != "*"
    error_message = "security_trail_role_pattern must be a role-name pattern narrower than \"*\"."
  }
}
