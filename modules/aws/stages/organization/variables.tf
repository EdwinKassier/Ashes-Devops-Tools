# -----------------------------------------------------------------------------
# Accounts
# -----------------------------------------------------------------------------

variable "accounts" {
  description = "Foundational member accounts to create, keyed by account name. Each entry sets the root email, the target OU name (must exist in the organization OU tree), optional alternate contacts, and optional tags. Defaults to the six SRA foundational accounts with placeholder emails the root is expected to override."
  type = map(object({
    email = string
    ou    = string
    # Display name of the account. Null = the map key. Set it when adopting an
    # existing account whose name differs from the key (adopt_existing).
    name = optional(string)
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
    # Display name of the account. Null = the map key. Set it when adopting an
    # existing account whose name differs from the key (adopt_existing).
    name = optional(string)
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
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.terraform_run_role_arn))
    error_message = "terraform_run_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/<name>) with no wildcards (* or ?)."
  }
}

variable "break_glass_role_arn" {
  description = "Account-qualified exact ARN of the emergency break-glass role. Carved out of every guardrail deny statement."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/<name>) with no wildcards (* or ?)."
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

variable "central_detection_account_keys" {
  description = "Account keys (from accounts) whose pipeline may change GuardDuty filters/detectors, CloudTrail selectors and Security Hub standards; denied everywhere else except break-glass (deny-tamper SCP). Default: the SRA security_tooling and log_archive accounts. Set [] to restore the pipeline-wide exemption."
  type        = list(string)
  default     = ["security_tooling", "log_archive"]
  nullable    = false

  # A typo would silently drop the SCP statement (and with it the scoping).
  validation {
    condition     = alltrue([for k in var.central_detection_account_keys : contains(keys(merge(var.accounts, var.workload_accounts)), k)])
    error_message = "central_detection_account_keys must name accounts in accounts / workload_accounts."
  }
}

variable "pin_tfc_federation_to_org" {
  description = "Deny (RCP, every account) sts:AssumeRoleWithWebIdentity with a <tfc_hostname> token whose sub is not organization:<tfc_organization>:*. Without it, any pipeline that can create a role can make it trust ANOTHER TFC org on the same issuer: a persistence path no permissions boundary sees. Default true; takes effect when tfc_organization is set. Set false only if workspaces in other TFC organizations must assume roles here."
  type        = bool
  default     = true
}

variable "github_federation_owners" {
  description = "GitHub users/orgs whose Actions OIDC tokens may assume roles anywhere in the organization (RCP pin: sub must be repo:<owner>/*). Empty (default) leaves GitHub federation unpinned. Set it to every owner whose repos deploy here (app-services deploy roles)."
  type        = list(string)
  default     = []
  nullable    = false
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
  description = "Cap every member-account tfc-apply role with a permissions boundary (default true). With tfc_apply_permissions_boundary_arn = null the StackSet embeds tfc-apply-boundary: allow-all except leaving the org, stopping/deleting CloudTrail/GuardDuty/Config, modifying the TFC roles/OIDC provider/boundary, creating IAM users/access keys, and (tfc_enable_apply_boundary_propagation) creating or granting to roles without the same boundary."
  type        = bool
  default     = true
}

variable "tfc_apply_permissions_boundary_arn" {
  description = "Optional existing permissions-boundary policy ARN for the tfc-apply roles (must exist in every bound account). Null (default) = the embedded tfc-apply-boundary."
  type        = string
  default     = null
}

variable "tfc_enable_apply_boundary_propagation" {
  description = "Make the embedded tfc-apply boundary self-propagating (default true): tfc-apply can only create / grant to roles carrying the same boundary and can never remove a boundary, closing the create-unbounded-role escape. Every aws_iam_role created by tfc-apply in a member account must then set permissions_boundary to the tfc-apply-boundary ARN."
  type        = bool
  default     = true
}

variable "tfc_enable_plan_role_data_read_deny" {
  description = "Attach an inline deny on data-plane reads (s3:GetObject*, secretsmanager:GetSecretValue, ssm:GetParameter*, kms:Decrypt, DynamoDB/SQS/Kinesis/Logs reads, ...) to every member-account tfc-plan role (default true)."
  type        = bool
  default     = true
}

variable "tfc_plan_role_data_read_exempt_arns" {
  description = "Resource ARNs excluded from the tfc-plan data-plane deny (NotResource), for Terraform-managed resources whose refresh reads data (e.g. the aws-workload SaaS bridge secret). Empty (default) = deny everywhere."
  type        = list(string)
  default     = []
}

variable "tfc_oidc_call_as" {
  description = "Manage the StackSet as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED_ADMIN)."
  type        = string
  default     = "SELF"
}

variable "enable_member_break_glass_role" {
  description = "Deploy the break-glass role into every member account (sibling StackSet of the TFC OIDC baseline, targeting the org root) so the SCP-exempt break-glass name is occupied and protected there instead of claimable by the first principal to create it. Rides on enable_tfc_oidc_baseline. Default true."
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
  description = "Require MFA (aws:MultiFactorAuthPresent + aws:MultiFactorAuthAge) on the member break-glass trust. Default true. A role-chained session may not carry MFA context: trust MFA-authenticated IAM users, or set false when the trusted management role is itself MFA-gated — validate end to end before relying on it."
  type        = bool
  default     = true
}

variable "enable_tfc_management_roles" {
  description = "Create a dedicated least-privilege management-account plan/apply role pair per management-default workspace (tfc_management_workspaces). tfc-admin binds them instead of the shared phase-0 management role, so aws-security / aws-backup cannot pivot into member accounts or change the org structure. Requires tfc_organization and the management account's TFC OIDC provider (phase 0). Default true."
  type        = bool
  default     = true
}

variable "tfc_management_workspaces" {
  description = "Management-default workspaces that get their own role pair (tfc-management-roles workspaces). aws-security and aws-backup have built-in least-privilege policies; others need apply_policy_json."
  type = map(object({
    project           = optional(string)
    apply_policy_json = optional(string)
  }))
  default = {
    "aws-security" = {}
    "aws-backup"   = {}
  }
}

variable "org_policy_overrides" {
  description = "Organization policies merged over the built-in guardrail set (organization-policy policy_overrides): an existing key replaces that policy's content, a new key adds one (attach it with org_policy_attachments). Use this instead of forking the stage."
  type = map(object({
    type    = string
    content = string
  }))
  default  = {}
  nullable = false
}

variable "disabled_org_policies" {
  description = "Built-in policy keys not to create; their default attachments are dropped too. Default: backup-policy (the aws-backup stage owns the attached BACKUP_POLICY, so the built-in copy would sit unattached)."
  type        = list(string)
  default     = ["backup-policy"]
  nullable    = false
}

variable "org_policy_attachments" {
  description = "Extra policy attachments (key => {policy_key, target_id}), e.g. for policies added through org_policy_overrides. Keys must not collide with the built-in attachment keys."
  type = map(object({
    policy_key = string
    target_id  = string
  }))
  default  = {}
  nullable = false
}

variable "create_backup_service_role" {
  description = "Deploy the member-account AWS Backup service role (backup_service_role_name) to every Workloads-OU account through a service-managed StackSet. aws-backup's BACKUP_POLICY references it, so aws-backup needs no CloudFormation rights. Default true."
  type        = bool
  default     = true
}

variable "backup_service_role_name" {
  description = "Name of the member-account AWS Backup service role (must equal aws-backup backup_role_name)."
  type        = string
  default     = "aws-backup-org-role"
}

variable "backup_service_role_stack_set_name" {
  description = "Name of the StackSet that deploys the Backup service role."
  type        = string
  default     = "aws-backup-org-role"
}

variable "backup_service_role_region" {
  description = "Region of the Backup service-role stack instances (IAM is global; one region suffices)."
  type        = string
  default     = "eu-west-2"
}

variable "github_federation_owner_ids" {
  description = "Numeric GitHub owner IDs whose Actions tokens may assume roles (RCP pin repository_owner_id:<id>:*), for deploy roles using the immutable-ID subject template. Complements github_federation_owners."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_builtin_web_identity_providers" {
  description = "Built-in web-identity providers roles may trust (cognito-identity.amazonaws.com, accounts.google.com, graph.facebook.com, www.amazon.com). Default none: the RCP denies sts:AssumeRoleWithWebIdentity with their tokens, since they need no IAM provider resource and so escape every other control."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "create_org_trail_delivery_role" {
  description = "Create the organization trail's CloudTrail -> CloudWatch Logs delivery role (<org_trail_name>-cloudwatch-delivery) here, so aws-security needs no IAM write in the management account. Default true."
  type        = bool
  default     = true
}

variable "org_trail_name" {
  description = "Name of the organization CloudTrail trail aws-security creates (cloudtrail-org trail_name)."
  type        = string
  default     = "org-trail"
}

variable "identity_center_admin_account_key" {
  description = "Account key (accounts / workload_accounts) to register as the IAM Identity Center delegated administrator. Default shared_services, the aws-identity account in the SRA layout. Null = do not register here."
  type        = string
  default     = "shared_services"

  validation {
    condition     = var.identity_center_admin_account_key == null || contains(keys(merge(var.accounts, var.workload_accounts)), coalesce(var.identity_center_admin_account_key, "x"))
    error_message = "identity_center_admin_account_key must name an account in accounts / workload_accounts."
  }
}

variable "partition" {
  description = "AWS partition the organization policies are rendered for (aws, aws-us-gov, aws-cn)."
  type        = string
  default     = "aws"
}
