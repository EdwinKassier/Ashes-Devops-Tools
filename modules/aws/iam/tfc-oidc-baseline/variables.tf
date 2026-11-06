# -----------------------------------------------------------------------------
# Terraform Cloud identity
# -----------------------------------------------------------------------------

variable "tfc_hostname" {
  description = "Hostname of the Terraform Cloud / Enterprise instance that issues the workload-identity tokens. Becomes the OIDC provider URL (https://<hostname>) and the prefix of the aud/sub condition keys."
  type        = string
  default     = "app.terraform.io"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?([.][a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.tfc_hostname))
    error_message = "tfc_hostname must be a bare DNS hostname (no scheme, path or port), e.g. app.terraform.io."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name. Matched LITERALLY in every trust policy sub condition — wildcards are rejected so no other TFC organization can ever assume the roles."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,90}$", var.tfc_organization))
    error_message = "tfc_organization must be 1-90 letters, digits, '-' or '_' (no wildcards)."
  }
}

variable "tfc_project" {
  description = "Default Terraform Cloud project the bound workspaces live in. Matched literally in the sub condition; override per binding with account_bindings[*].project."
  type        = string
  default     = "Default Project"

  validation {
    condition     = can(regex("^[A-Za-z0-9 _-]{1,90}$", var.tfc_project))
    error_message = "tfc_project must be 1-90 letters, digits, spaces, '-' or '_' (no wildcards)."
  }
}

variable "account_bindings" {
  description = "Map of account key -> binding. Each binding names the member account (account_id), the TFC workspaces allowed to assume its tfc-plan/tfc-apply roles, and an optional TFC project override. Workspace names are matched exactly unless allow_workspace_wildcards is true. Accounts in a targeted OU without a binding receive only the OIDC provider (no roles)."
  type = map(object({
    account_id = string
    workspaces = list(string)
    project    = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.account_bindings) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", k))])
    error_message = "account_bindings keys must be 1-64 letters, digits, '-' or '_', starting with a letter or digit."
  }

  # Keys become CloudFormation logical-ID suffixes (non-alphanumerics removed,
  # segments title-cased); two keys must not collapse to the same suffix.
  validation {
    condition = length(distinct([
      for k in keys(var.account_bindings) : join("", [for p in split("_", replace(k, "-", "_")) : title(p)])
    ])) == length(var.account_bindings)
    error_message = "account_bindings keys must stay unique after removing '-'/'_' and title-casing (they become CloudFormation logical IDs)."
  }

  validation {
    condition     = alltrue([for b in values(var.account_bindings) : length(b.workspaces) > 0])
    error_message = "Every account_bindings entry must list at least one workspace."
  }

  validation {
    condition = alltrue(flatten([
      for b in values(var.account_bindings) : [
        for ws in b.workspaces : var.allow_workspace_wildcards ? (
          can(regex("^[A-Za-z0-9_*-]{1,90}$", ws)) && ws != "*"
        ) : can(regex("^[A-Za-z0-9_-]{1,90}$", ws))
      ]
    ]))
    error_message = "Workspace names must be 1-90 letters, digits, '-' or '_'. '*' is allowed only when allow_workspace_wildcards = true, and never as a bare '*'."
  }

  validation {
    condition     = alltrue([for b in values(var.account_bindings) : b.project == null || can(regex("^[A-Za-z0-9 _-]{1,90}$", coalesce(b.project, "x")))])
    error_message = "account_bindings[*].project must be 1-90 letters, digits, spaces, '-' or '_' (no wildcards)."
  }
}

variable "allow_workspace_wildcards" {
  description = "Allow '*' inside workspace names in account_bindings (e.g. aws-workload-*), switching the sub condition from StringEquals to StringLike. The organization and project are always matched literally. Default false: exact workspace names only."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Roles
# -----------------------------------------------------------------------------

variable "plan_role_name" {
  description = "Name of the read-only role TFC assumes during the plan phase (TFC_AWS_PLAN_ROLE_ARN)."
  type        = string
  default     = "tfc-plan"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.plan_role_name))
    error_message = "plan_role_name must be a valid IAM role name (1-64 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "apply_role_name" {
  description = "Name of the role TFC assumes during the apply phase (TFC_AWS_APPLY_ROLE_ARN)."
  type        = string
  default     = "tfc-apply"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.apply_role_name))
    error_message = "apply_role_name must be a valid IAM role name (1-64 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "plan_role_policy_arns" {
  description = "Managed policy ARNs attached to the plan role. Must be read-only: AdministratorAccess, PowerUserAccess and IAMFullAccess are rejected."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  validation {
    condition     = length(var.plan_role_policy_arns) > 0 && alltrue([for a in var.plan_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "plan_role_policy_arns must be a non-empty list of IAM managed policy ARNs."
  }

  validation {
    condition     = alltrue([for a in var.plan_role_policy_arns : !can(regex(":policy/(AdministratorAccess|PowerUserAccess|IAMFullAccess)$", a))])
    error_message = "plan_role_policy_arns must not grant write access (AdministratorAccess / PowerUserAccess / IAMFullAccess are rejected) — speculative PR plans run with this role."
  }
}

variable "apply_role_policy_arns" {
  description = "Managed policy ARNs attached to the apply role. Defaults to AdministratorAccess (the apply role provisions arbitrary landing-zone resources), capped by the apply permissions boundary (enable_apply_permissions_boundary); narrow it per organization if your layers allow."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  validation {
    condition     = length(var.apply_role_policy_arns) > 0 && alltrue([for a in var.apply_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "apply_role_policy_arns must be a non-empty list of IAM managed policy ARNs."
  }
}

variable "enable_apply_permissions_boundary" {
  description = "Cap the apply role with a permissions boundary (default true). With apply_permissions_boundary_arn = null the StackSet embeds a managed boundary that allows everything EXCEPT: leaving the org; stopping/deleting CloudTrail, GuardDuty and Config; modifying the plan/apply roles, the OIDC provider or the boundary itself; and iam:CreateUser/CreateAccessKey/CreateLoginProfile."
  type        = bool
  default     = true
}

variable "apply_permissions_boundary_arn" {
  description = "Optional existing permissions-boundary policy ARN to use instead of the embedded one. The policy must already exist in every bound account (an AWS-managed policy, or a same-named customer policy deployed by another StackSet). Null (default) = the embedded boundary. Ignored when enable_apply_permissions_boundary = false."
  type        = string
  default     = null

  validation {
    condition     = var.apply_permissions_boundary_arn == null || can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", var.apply_permissions_boundary_arn))
    error_message = "apply_permissions_boundary_arn must be null or an IAM managed policy ARN."
  }
}

variable "apply_boundary_policy_name" {
  description = "Name of the embedded permissions-boundary managed policy created in each targeted account."
  type        = string
  default     = "tfc-apply-boundary"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.apply_boundary_policy_name))
    error_message = "apply_boundary_policy_name must be a valid IAM policy name (1-128 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "max_session_duration" {
  description = "Maximum session duration (seconds) for both roles. TFC requests 1 hour by default."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "oidc_thumbprints" {
  description = "Optional OIDC provider certificate thumbprints. AWS validates TFC's certificate against its trusted CA library, so the default (empty) omits ThumbprintList."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for t in var.oidc_thumbprints : can(regex("^[0-9a-fA-F]{40}$", t))])
    error_message = "Each oidc_thumbprints entry must be a 40-hex-character SHA-1 thumbprint."
  }
}

variable "partition" {
  description = "AWS partition used to build the role ARN outputs."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "aws-us-gov", "aws-cn"], var.partition)
    error_message = "partition must be one of aws, aws-us-gov, aws-cn."
  }
}

# -----------------------------------------------------------------------------
# StackSet
# -----------------------------------------------------------------------------

variable "stack_set_name" {
  description = "Name of the SERVICE_MANAGED CloudFormation StackSet that deploys the baseline."
  type        = string
  default     = "tfc-oidc-baseline"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,127}$", var.stack_set_name))
    error_message = "stack_set_name must start with a letter and contain only letters, digits and '-' (max 128)."
  }
}

variable "call_as" {
  description = "Whether the StackSet is managed from the management account (SELF) or a CloudFormation delegated-administrator account (DELEGATED_ADMIN)."
  type        = string
  default     = "SELF"

  validation {
    condition     = contains(["SELF", "DELEGATED_ADMIN"], var.call_as)
    error_message = "call_as must be SELF or DELEGATED_ADMIN."
  }
}

variable "target_ou_ids" {
  description = "Map of stable OU name -> OU ID the StackSet deploys to (one stack instance per OU). Every account in these OUs (including accounts that join later, via auto-deployment) receives the OIDC provider; bound accounts also receive the roles. Service-managed StackSets never deploy to the management account."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for id in values(var.target_ou_ids) : can(regex("^(ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}|r-[a-z0-9]{4,32})$", id))])
    error_message = "target_ou_ids values must be OU IDs (ou-xxxx-xxxxxxxx) or an organization root ID (r-xxxx)."
  }
}

variable "stack_set_instance_region" {
  description = "Single region the stack instances are deployed to. IAM is global, so the baseline must be deployed to exactly ONE region (a second region would collide on role names). null = the provider's region."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the StackSet (propagated by CloudFormation to the IAM resources it creates)."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Escape-hatch hardening
# -----------------------------------------------------------------------------

variable "enable_apply_boundary_propagation" {
  description = "Make the embedded tfc-apply boundary self-propagating (default true): tfc-apply may only CreateRole / PutRolePermissionsBoundary / AttachRolePolicy / PutRolePolicy when the target role carries this same boundary (iam:PermissionsBoundary), and may never delete a permissions boundary. Without it the apply identity can create an unbounded role, attach AdministratorAccess and assume it. Every aws_iam_role created by tfc-apply in a member account must then set permissions_boundary to arn:<partition>:iam::<account>:policy/<apply_boundary_policy_name>. Applies to the embedded boundary only (apply_permissions_boundary_arn = null)."
  type        = bool
  default     = true
}

variable "enable_plan_role_data_read_deny" {
  description = "Attach an inline deny to the plan role for data-plane reads that ReadOnlyAccess otherwise grants (s3:GetObject*, secretsmanager:GetSecretValue, ssm:GetParameter*, kms:Decrypt, DynamoDB item reads, sqs:ReceiveMessage, kinesis:GetRecords, CloudWatch Logs event reads/queries, rds-data, Athena/Redshift Data results, ECR image pulls). Default true: speculative PR plans run as this role, so it reads configuration, not data."
  type        = bool
  default     = true
}

variable "plan_role_data_read_exempt_arns" {
  description = "Resource ARNs (patterns allowed) excluded from the plan-role data-plane deny (rendered as NotResource). Use for Terraform-managed resources whose refresh reads data, e.g. an aws_secretsmanager_secret_version or aws_s3_object the plan must diff. Empty (default) = deny on every resource."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.plan_role_data_read_exempt_arns : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[^:]*:[^:]*:.*[A-Za-z0-9]", a))])
    error_message = "plan_role_data_read_exempt_arns entries must be resource ARNs naming a resource (not a bare service-wide wildcard such as arn:aws:s3:::*)."
  }
}
