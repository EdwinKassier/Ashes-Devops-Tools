# -----------------------------------------------------------------------------
# Provider region (management account)
#
# NB: the Terraform Cloud organization for this phase-1 producer root's backend
# is supplied to `terraform init` via the TF_CLOUD_ORGANIZATION environment variable (see
# backend.tf) — a backend block cannot reference variables, so there is no
# tfc_organization variable here (unlike the consumer roots, which reference it
# inside a terraform_remote_state data source).
# -----------------------------------------------------------------------------

variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "management_account_id" {
  description = "12-digit AWS management (payer) account ID. The default provider sets allowed_account_ids to this, so Terraform fails fast if the resolved credentials are a different account (audit C4). Null = aws.management_account_id from config/landing-zone.yaml (quote it there); no built-in default."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[0-9]{12}$", coalesce(var.management_account_id, local.cfg.management_account_id, "!unset")))
    error_message = "management_account_id is unset or invalid: set var.management_account_id or aws.management_account_id in config/landing-zone.yaml (quoted) to the 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Primary AWS region for the default (management-account) provider, e.g. eu-west-2. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (or org.regions.aws in config/landing-zone.yaml) must be a valid AWS region name, e.g. eu-west-2."
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
  description = "Foundational member accounts to create, keyed by account name. Each entry sets the root email, the target OU name (must exist in the organization OU tree), optional alternate contacts, and optional tags. Null = aws.accounts from config/landing-zone.yaml, else the six SRA foundational accounts with placeholder emails (rejected below, so they must be overridden)."
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
  default = null

  validation {
    condition     = alltrue([for e in(var.accounts != null ? [for a in values(var.accounts) : a.email] : [for a in values(local.cfg_or_default_accounts) : a.email]) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every accounts entry (var.accounts or aws.accounts in config/landing-zone.yaml) must have a valid root email address."
  }

  # L2: the default emails are placeholders. Reject them so an unmodified apply
  # fails fast instead of trying to create real AWS accounts with example.com
  # addresses (each account needs a unique, deliverable root email).
  validation {
    # [@.] also catches subdomains of the reserved example domains (e.g. @acme.example.com).
    condition     = alltrue([for e in(var.accounts != null ? [for a in values(var.accounts) : a.email] : [for a in values(local.cfg_or_default_accounts) : a.email]) : !can(regex("[@.]example\\.(com|org|net)$", lower(e)))])
    error_message = "accounts still uses placeholder @example.com emails. Set real, unique root email addresses for each account (var.accounts or aws.accounts in config/landing-zone.yaml) before applying."
  }
}

variable "workload_accounts" {
  description = "Additional workload member accounts to create, keyed by account name. Merged with var.accounts by the stage; same object shape. Null = aws.workload_accounts from config/landing-zone.yaml, else {}."
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
  default = null

  validation {
    condition     = alltrue([for e in(var.workload_accounts != null ? [for a in values(var.workload_accounts) : a.email] : [for a in values(local.cfg.workload_accounts) : a.email]) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every workload_accounts entry (var.workload_accounts or aws.workload_accounts in config/landing-zone.yaml) must have a valid root email address."
  }

  validation {
    condition     = alltrue([for e in(var.workload_accounts != null ? [for a in values(var.workload_accounts) : a.email] : [for a in values(local.cfg.workload_accounts) : a.email]) : !can(regex("[@.]example\\.(com|org|net)$", lower(e)))])
    error_message = "workload_accounts still uses placeholder example.com/org/net emails. Set real, unique root email addresses before applying."
  }
}

# -----------------------------------------------------------------------------
# Guardrail inputs
# -----------------------------------------------------------------------------

variable "allowed_regions" {
  description = "Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out). Null = aws.allowed_regions from config/landing-zone.yaml, else [\"eu-west-2\"]."
  type        = list(string)
  default     = null

  validation {
    condition     = length(var.allowed_regions != null ? var.allowed_regions : coalesce(local.cfg.allowed_regions, ["eu-west-2"])) > 0
    error_message = "allowed_regions (or aws.allowed_regions in config/landing-zone.yaml) must contain at least one region."
  }
}

variable "terraform_run_role_arn" {
  description = "Account-qualified exact ARN of the MANAGEMENT-account Terraform Cloud apply role (the phase-0, hand-created role from the aws-bootstrap runbook Step 2, e.g. arn:aws:iam::<mgmt>:role/tfc-mgmt-apply; the same ARN tfc-admin sets as TFC_AWS_APPLY_ROLE_ARN via aws_management_apply_role_arn). Carved out of every guardrail deny statement so automation is not locked out. Not created by this root: StackSets never deploy to the management account. Null = aws.terraform_run_role_arn from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", coalesce(var.terraform_run_role_arn, local.cfg.terraform_run_role_arn, "!unset")))
    error_message = "terraform_run_role_arn is unset or invalid: set var.terraform_run_role_arn or aws.terraform_run_role_arn in config/landing-zone.yaml to an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "break_glass_role_arn" {
  description = "Account-qualified exact ARN of the emergency break-glass role in the management account. Carved out of every guardrail deny statement. Either hand-create it in phase-0 (aws-bootstrap runbook Step 2) or let aws-security create it (create_break_glass = true, role name break_glass_role_name) and pass the ARN it will have here (arn:aws:iam::<mgmt>:role/<break_glass_role_name>); an SCP carve-out may name a role that does not exist yet. Null = aws.break_glass_role_arn from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", coalesce(var.break_glass_role_arn, local.cfg.break_glass_role_arn, "!unset")))
    error_message = "break_glass_role_arn is unset or invalid: set var.break_glass_role_arn or aws.break_glass_role_arn in config/landing-zone.yaml to an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP. Null = aws.log_archive_bucket_name from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(coalesce(var.log_archive_bucket_name, local.cfg.log_archive_bucket_name, " "))) > 0
    error_message = "log_archive_bucket_name is unset: set var.log_archive_bucket_name or aws.log_archive_bucket_name in config/landing-zone.yaml to a non-empty S3 bucket name."
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
  description = "Terraform Cloud organization whose workspaces the member-account roles trust. Matched literally (no wildcards). Required when enable_tfc_oidc_baseline is true. Not the same mechanism as the cloud-block organization (TF_CLOUD_ORGANIZATION), but normally the same value. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = var.enable_tfc_oidc_baseline ? (var.tfc_organization != null || local.cfg.tfc_organization != null) : true
    error_message = "tfc_organization is required when enable_tfc_oidc_baseline is true: set var.tfc_organization or org.tfc.organization in config/landing-zone.yaml."
  }
}

variable "tfc_hostname" {
  description = "Terraform Cloud / Enterprise hostname issuing workload-identity tokens."
  type        = string
  default     = "app.terraform.io"
}

variable "tfc_project" {
  description = "Default TFC project of the bound workspaces (matched literally in the trust sub). Override per account with tfc_workspace_bindings[*].project. Null = org.tfc.aws_project from config/landing-zone.yaml, else <org.tfc.project_name_prefix>aws, i.e. landing-zone-aws: the project tfc-admin puts the aws-* workspaces in (<project_name_prefix>aws)."
  type        = string
  default     = null
}

variable "tfc_workspace_bindings" {
  description = "Map of account key (from accounts / workload_accounts) -> TFC workspaces allowed to assume that account's tfc-plan / tfc-apply roles (optional per-account project override). Null = the six foundational bindings plus one per aws.workload_environments entry in config/landing-zone.yaml (account_key => aws-workload-<env>), so tfc-admin's workload workspaces and these trusts come from the same source. An explicit map replaces that derivation entirely: then ADD one entry per workload account, e.g. workload_dev = { workspaces = [\"aws-workload-dev\"] }."
  type = map(object({
    workspaces = list(string)
    project    = optional(string)
  }))
  default = null
}

variable "tfc_oidc_allow_workspace_wildcards" {
  description = "Allow '*' inside bound workspace names (StringLike). The organization and project are always literal. Default false: exact names."
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

variable "enable_member_break_glass_role" {
  description = "Deploy the break-glass role into every member account (StackSet targeting the org root) so the SCP-exempt break-glass name is occupied and protected there. Rides on enable_tfc_oidc_baseline. Default true."
  type        = bool
  default     = true
}

variable "member_break_glass_trusted_principal_arns" {
  description = "Account-qualified management-account principal ARNs (role or user) the member break-glass role trusts. Empty (default) = [break_glass_role_arn]."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.member_break_glass_trusted_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]+$", a))])
    error_message = "member_break_glass_trusted_principal_arns entries must be account-qualified IAM role/user ARNs without wildcards."
  }
}

variable "member_break_glass_require_mfa" {
  description = "Require MFA on the member break-glass trust (default true). A role-chained session may not carry MFA context: trust MFA-authenticated IAM users, or set false when the trusted management role is itself MFA-gated."
  type        = bool
  default     = true
}

variable "allow_vpc_bpa_exclusions" {
  description = "Allow member accounts to create VPC Block Public Access exclusions under the org declarative EC2 policy. Default false (no VPC can bypass the org-wide internet-gateway ingress block). Set true only if an aws-workload environment uses app_ingress_mode = \"public_alb\"; that root then excludes only its own spoke VPC. cloudfront_vpc_origin needs no exclusion."
  type        = bool
  default     = false
}

variable "pin_tfc_federation_to_org" {
  description = "RCP: accept app.terraform.io (tfc_hostname) web-identity tokens org-wide only from tfc_organization, so no pipeline can make a role trust another TFC org. Default true."
  type        = bool
  default     = true
}

variable "github_federation_owners" {
  description = "GitHub users/orgs whose Actions OIDC tokens may assume roles in the organization (RCP pin repo:<owner>/*). Null = aws.github_federation_owners from config/landing-zone.yaml, else empty (GitHub federation unpinned)."
  type        = list(string)
  default     = null
}
