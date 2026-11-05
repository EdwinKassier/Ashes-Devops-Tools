# -----------------------------------------------------------------------------
# Accounts
# -----------------------------------------------------------------------------

variable "accounts" {
  description = "Foundational member accounts to create, keyed by account name. Each entry sets the root email, the target OU name (must exist in the organization OU tree), optional alternate contacts, and optional tags. Defaults to the six SRA foundational accounts with placeholder emails the root is expected to override."
  type = map(object({
    email = string
    ou    = string
    alternate_contacts = optional(map(object({
      contact_type  = string
      name          = string
      title         = string
      email_address = string
      phone_number  = string
    })), {})
    tags = optional(map(string), {})
  }))
  default = {
    log_archive      = { email = "aws+log-archive@example.com", ou = "Security" }
    security_tooling = { email = "aws+security-tooling@example.com", ou = "Security" }
    network          = { email = "aws+network@example.com", ou = "Infrastructure" }
    shared_services  = { email = "aws+shared-services@example.com", ou = "Infrastructure" }
    backup           = { email = "aws+backup@example.com", ou = "Infrastructure" }
    forensics        = { email = "aws+forensics@example.com", ou = "Security" }
  }

  validation {
    condition     = alltrue([for a in values(var.accounts) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", a.email))])
    error_message = "Every accounts entry must have a valid root email address."
  }
}

variable "workload_accounts" {
  description = "Additional workload member accounts to create, keyed by account name. Merged with var.accounts; same object shape."
  type = map(object({
    email = string
    ou    = string
    alternate_contacts = optional(map(object({
      contact_type  = string
      name          = string
      title         = string
      email_address = string
      phone_number  = string
    })), {})
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.workload_accounts) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", a.email))])
    error_message = "Every workload_accounts entry must have a valid root email address."
  }
}

# -----------------------------------------------------------------------------
# Guardrail inputs
# -----------------------------------------------------------------------------

variable "allowed_regions" {
  description = "Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out)."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "allowed_regions must contain at least one region."
  }
}

variable "terraform_run_role_arn" {
  description = "Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every guardrail deny statement so automation is not locked out."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.terraform_run_role_arn))
    error_message = "terraform_run_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "break_glass_role_arn" {
  description = "Account-qualified exact ARN of the emergency break-glass role. Carved out of every guardrail deny statement."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "pipeline_role_names" {
  description = "Member-account Terraform pipeline role names (or name patterns) passed to the deny-tamper SCP. Rendered as arn:aws:iam::*:role/<name>: exempt from the security-service reconfiguration denies and protected from IAM modification. SCPs never apply to the management account, so these must be the roles that run IN member accounts."
  type        = list(string)
  default     = ["tfc-apply", "OrganizationAccountAccessRole", "stacksets-exec-*"]
}

variable "break_glass_role_names" {
  description = "Member-account break-glass role names for the deny-tamper SCP (sole exemption from the destructive statements). Empty (default) derives the name from break_glass_role_arn."
  type        = list(string)
  default     = []
}

variable "data_perimeter_trusted_account_ids" {
  description = "Optional 12-digit account IDs outside the organization trusted by the RCP data perimeter (aws:PrincipalAccount / aws:SourceAccount). Empty (default) trusts only the organization."
  type        = list(string)
  default     = []
}

variable "allow_vpc_bpa_exclusions" {
  description = "Whether member accounts may create VPC Block Public Access exclusions under the declarative EC2 policy. Default false."
  type        = bool
  default     = false
}

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

# -----------------------------------------------------------------------------
# Cost governance (management-account-scoped)
# -----------------------------------------------------------------------------

variable "enable_cost_governance" {
  description = "Gate for the cost-governance module (budgets, Cost Anomaly Detection, cost-allocation tags). When false the module composes as a no-op."
  type        = bool
  default     = true
}

variable "budgets" {
  description = "Monthly COST budgets keyed by budget name, passed to the cost-governance module. limit_amount is the USD limit; threshold_percent triggers an ACTUAL-spend notification; emails receive the notification."
  type = map(object({
    limit_amount      = string
    threshold_percent = number
    emails            = optional(list(string), [])
  }))
  default = {
    org-monthly = {
      limit_amount      = "1000"
      threshold_percent = 80
    }
  }
}

variable "cost_allocation_tags" {
  description = "Tag keys to activate as cost-allocation tags in Cost Explorer / the Cost & Usage Report. Should mirror the tag-policy keys."
  type        = list(string)
  default     = ["CostCenter", "Environment", "Owner"]
}

variable "cost_notifications_topic_arn" {
  description = "Optional SNS topic ARN that budget notifications are published to, in addition to per-budget email subscribers. Empty string disables SNS fan-out."
  type        = string
  default     = ""
}

variable "cost_anomaly_email" {
  description = "Email address that receives Cost Anomaly Detection alerts."
  type        = string
  default     = "finops@example.com"
}

# -----------------------------------------------------------------------------
# Terraform Cloud OIDC baseline (member-account workload identity)
#
# A SERVICE_MANAGED StackSet deploys an app.terraform.io OIDC provider plus
# per-workspace tfc-plan (read-only) / tfc-apply roles into every bound member
# account, so downstream workspaces authenticate DIRECTLY into their own account
# instead of running with management-account credentials + OrganizationAccountAccessRole.
# -----------------------------------------------------------------------------

variable "enable_tfc_oidc_baseline" {
  description = "Gate for the TFC OIDC baseline StackSet (OIDC provider + tfc-plan/tfc-apply roles in member accounts). Requires tfc_organization when true."
  type        = bool
  default     = true
}

variable "tfc_organization" {
  description = "Terraform Cloud organization whose workspaces the member-account roles trust (matched literally, never wildcarded). Required when enable_tfc_oidc_baseline is true."
  type        = string
  default     = null

  validation {
    condition     = var.enable_tfc_oidc_baseline ? var.tfc_organization != null : true
    error_message = "tfc_organization is required when enable_tfc_oidc_baseline is true."
  }
}

variable "tfc_hostname" {
  description = "Terraform Cloud / Enterprise hostname issuing the workload-identity tokens."
  type        = string
  default     = "app.terraform.io"
}

variable "tfc_project" {
  description = "Default TFC project of the bound workspaces (matched literally in the trust sub). Override per account with tfc_workspace_bindings[*].project."
  type        = string
  default     = "Default Project"
}

variable "tfc_workspace_bindings" {
  description = "Map of account key (from accounts / workload_accounts) -> TFC workspaces allowed to assume that account's tfc-plan / tfc-apply roles, with an optional project override. Add one entry per workload account, e.g. workload_dev = { workspaces = [\"aws-workload-dev\"] }. The multi-account aws-security root is bound into security_tooling, log_archive and forensics; aws-backup into backup."
  type = map(object({
    workspaces = list(string)
    project    = optional(string)
  }))
  default = {
    security_tooling = { workspaces = ["aws-security"] }
    log_archive      = { workspaces = ["aws-security"] }
    forensics        = { workspaces = ["aws-security"] }
    network          = { workspaces = ["aws-network"] }
    shared_services  = { workspaces = ["aws-identity", "aws-shared-services"] }
    backup           = { workspaces = ["aws-backup"] }
  }

  validation {
    condition     = alltrue([for k in keys(var.tfc_workspace_bindings) : contains(concat(keys(var.accounts), keys(var.workload_accounts)), k)])
    error_message = "Every tfc_workspace_bindings key must be an account key defined in accounts or workload_accounts."
  }
}

variable "tfc_oidc_allow_workspace_wildcards" {
  description = "Allow '*' inside bound workspace names (StringLike sub match). The organization and project are always literal. Default false: exact workspace names."
  type        = bool
  default     = false
}

variable "tfc_apply_role_policy_arns" {
  description = "Managed policy ARNs attached to every member-account tfc-apply role (capped by the apply permissions boundary, tfc_enable_apply_permissions_boundary)."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "tfc_enable_apply_permissions_boundary" {
  description = "Cap every member-account tfc-apply role with a permissions boundary (default true). With tfc_apply_permissions_boundary_arn = null the StackSet embeds tfc-apply-boundary: allow-all except leaving the org, stopping/deleting CloudTrail/GuardDuty/Config, modifying the TFC roles/OIDC provider/boundary, and creating IAM users/access keys."
  type        = bool
  default     = true
}

variable "tfc_apply_permissions_boundary_arn" {
  description = "Optional existing permissions-boundary policy ARN for the tfc-apply roles (must exist in every bound account). Null (default) = the embedded tfc-apply-boundary."
  type        = string
  default     = null
}

variable "tfc_oidc_call_as" {
  description = "Manage the StackSet as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED_ADMIN)."
  type        = string
  default     = "SELF"
}
