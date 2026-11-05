# -----------------------------------------------------------------------------
# Provider region (management account)
#
# NB: the Terraform Cloud organization for this phase-1 producer root's backend
# is supplied to `terraform init` via backend.hcl / TF_CLI_ARGS_init (see
# backend.tf) — a backend block cannot reference variables, so there is no
# tfc_organization variable here (unlike the consumer roots, which reference it
# inside a terraform_remote_state data source).
# -----------------------------------------------------------------------------

variable "management_account_id" {
  description = "12-digit AWS management (payer) account ID. The default provider sets allowed_account_ids to this, so Terraform fails fast if the resolved credentials are a different account (audit C4). No default: admins must state their own payer account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Primary AWS region for the default (management-account) provider, e.g. eu-west-2."
  type        = string
  default     = "eu-west-2"

  # AWS region names are short (well under the RE2 1000-repeat cap). Shape:
  # <geo>-<direction>-<number>, e.g. eu-west-2, us-east-1, ap-southeast-3.
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

# -----------------------------------------------------------------------------
# Accounts
#
# Defaults to the six SRA foundational accounts with PLACEHOLDER emails. The root
# operator MUST override these with real, unique root emails in terraform.tfvars
# before apply — AWS rejects duplicate root emails and the placeholders below are
# not deliverable addresses.
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

  # L2: the default emails are placeholders. Reject them so an unmodified apply
  # fails fast instead of trying to create real AWS accounts with example.com
  # addresses (each account needs a unique, deliverable root email).
  validation {
    # [@.] also catches subdomains of the reserved example domains (e.g. @acme.example.com).
    condition     = alltrue([for a in values(var.accounts) : !can(regex("[@.]example\\.(com|org|net)$", lower(a.email)))])
    error_message = "accounts still uses placeholder @example.com emails. Set real, unique root email addresses for each account before applying."
  }
}

variable "workload_accounts" {
  description = "Additional workload member accounts to create, keyed by account name. Merged with var.accounts by the stage; same object shape."
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

  validation {
    condition     = alltrue([for a in values(var.workload_accounts) : !can(regex("[@.]example\\.(com|org|net)$", lower(a.email)))])
    error_message = "workload_accounts still uses placeholder example.com/org/net emails. Set real, unique root email addresses before applying."
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
#
# Budgets, Cost Anomaly Detection and cost-allocation-tag activation live in the
# management account. Defaults are usable as-is; override in terraform.tfvars to
# set real budget limits, an SNS topic, and a real FinOps alert address.
# -----------------------------------------------------------------------------

variable "enable_cost_governance" {
  description = "Gate for the cost-governance module (budgets, Cost Anomaly Detection, cost-allocation tags). When false the module composes as a no-op."
  type        = bool
  default     = true
}

variable "budgets" {
  description = "Monthly COST budgets keyed by budget name. limit_amount is the USD limit; threshold_percent triggers an ACTUAL-spend notification; emails receive the notification."
  type = map(object({
    limit_amount      = string
    threshold_percent = number
    emails            = optional(list(string), [])
  }))
  # Default limit sized above the landing-zone idle baseline (the AWS security +
  # network hub is ~USD 1,500/month before any workload) so the alert is not
  # already breached on day one (FinOps F1). Set this to your real budget.
  default = {
    org-monthly = {
      limit_amount      = "3000"
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
# Terraform Cloud OIDC baseline (member-account workload identity)
#
# A SERVICE_MANAGED CloudFormation StackSet deploys an app.terraform.io OIDC
# provider plus tfc-plan (ReadOnlyAccess) / tfc-apply roles into each bound
# member account. Each role trusts ONLY
#   <tfc_hostname>:sub = organization:<tfc_organization>:project:<project>:workspace:<ws>:run_phase:<plan|apply>
#   <tfc_hostname>:aud = aws.workload.identity
# so downstream workspaces authenticate DIRECTLY into their own account and
# management-account credentials are used only by this root (and the
# management-account default provider of aws-security / aws-backup). The
# resulting ARNs are published as tfc_plan_role_arns / tfc_apply_role_arns.
# -----------------------------------------------------------------------------

variable "enable_tfc_oidc_baseline" {
  description = "Deploy the TFC OIDC baseline StackSet (OIDC provider + tfc-plan/tfc-apply roles) into the bound member accounts. Requires tfc_organization."
  type        = bool
  default     = true
}

variable "tfc_organization" {
  description = "Terraform Cloud organization whose workspaces the member-account roles trust. Matched literally (no wildcards). Required when enable_tfc_oidc_baseline is true. Not the same mechanism as the backend organization (backend.hcl), but normally the same value."
  type        = string
  default     = null

  validation {
    condition     = var.enable_tfc_oidc_baseline ? var.tfc_organization != null : true
    error_message = "tfc_organization is required when enable_tfc_oidc_baseline is true."
  }
}

variable "tfc_hostname" {
  description = "Terraform Cloud / Enterprise hostname issuing workload-identity tokens."
  type        = string
  default     = "app.terraform.io"
}

variable "tfc_project" {
  description = "Default TFC project of the bound workspaces (matched literally in the trust sub). Override per account with tfc_workspace_bindings[*].project."
  type        = string
  default     = "Default Project"
}

variable "tfc_workspace_bindings" {
  description = "Map of account key (from accounts / workload_accounts) -> TFC workspaces allowed to assume that account's tfc-plan / tfc-apply roles (optional per-account project override). Add one entry per workload account, e.g. workload_dev = { workspaces = [\"aws-workload-dev\"] }."
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
}

variable "tfc_oidc_allow_workspace_wildcards" {
  description = "Allow '*' inside bound workspace names (StringLike). The organization and project are always literal. Default false: exact names."
  type        = bool
  default     = false
}

variable "tfc_apply_role_policy_arns" {
  description = "Managed policy ARNs attached to every member-account tfc-apply role."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
