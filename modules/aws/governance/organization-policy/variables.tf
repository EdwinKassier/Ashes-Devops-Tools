# -----------------------------------------------------------------------------
# Organization identity + perimeter inputs
# -----------------------------------------------------------------------------

variable "org_id" {
  description = "AWS Organizations organization ID (o-xxxxxxxxxx). Used as the org-identity anchor in the RCP data-perimeter policy."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be an AWS Organizations org ID of the form o-xxxxxxxxxx."
  }
}

variable "allowed_regions" {
  description = "Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out)."
  type        = list(string)
  default     = ["eu-west-2", "eu-west-1"]

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "allowed_regions must contain at least one region."
  }
}

# -----------------------------------------------------------------------------
# Carve-out principals — must be account-qualified exact ARNs (no ::*:: wildcards)
# -----------------------------------------------------------------------------

variable "terraform_run_role_arn" {
  description = "Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every deny statement so automation is not locked out."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.terraform_run_role_arn))
    error_message = "terraform_run_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "break_glass_role_arn" {
  description = "Account-qualified exact ARN of the emergency break-glass role. Carved out of every deny statement."
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
# Member-account carve-outs for the deny-tamper SCP (role-name patterns)
#
# SCPs never apply to the management account, so deny-tamper exemptions must
# match MEMBER-account sessions. These names render as
# arn:aws:iam::*:role/<name> in aws:PrincipalArn conditions.
# -----------------------------------------------------------------------------

variable "pipeline_role_names" {
  description = "Names or name patterns (optionally path-prefixed, e.g. \"automation/tfc-apply\" or \"stacksets-exec-*\") of the member-account Terraform pipeline roles. Rendered as arn:aws:iam::*:role/<name> and exempted from the deny-tamper reconfiguration statements (Config recorders, GuardDuty/CloudTrail settings, flow logs, protected KMS key policies). These roles are also protected from IAM modification by anyone other than themselves or break-glass. NOT exempt from the destructive statements (break-glass only)."
  type        = list(string)
  default     = ["tfc-apply", "OrganizationAccountAccessRole", "stacksets-exec-*"]

  validation {
    condition     = length(var.pipeline_role_names) > 0 && alltrue([for n in var.pipeline_role_names : can(regex("^[A-Za-z0-9+=,.@_/*-]{1,512}$", n)) && !can(regex("^[*/]*$", n))])
    error_message = "pipeline_role_names must be a non-empty list of IAM role names or name patterns (optionally path-prefixed, e.g. stacksets-exec-*); a bare \"*\" is not allowed."
  }
}

variable "break_glass_role_names" {
  description = "Names of the break-glass role as it exists in MEMBER accounts. Rendered as arn:aws:iam::*:role/<name> and the sole exemption from the destructive deny-tamper statements. Empty (default) derives the name from break_glass_role_arn — a role with that name must then exist in each member account for break-glass to work there."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.break_glass_role_names : can(regex("^[A-Za-z0-9+=,.@_/-]{1,512}$", n))])
    error_message = "break_glass_role_names entries must be IAM role names without wildcards (optionally path-prefixed)."
  }
}

variable "kms_protection_tag_key" {
  description = "Resource-tag key marking KMS keys protected by the deny-tamper SCP. Keys tagged <key> = \"true\" cannot be scheduled for deletion, disabled, have rotation disabled or the tag removed except by break-glass; their key policy can only be changed by the pipeline roles or break-glass. Must match the tag the aws/data/kms-key module applies (protection_tag_key)."
  type        = string
  default     = "protected"

  validation {
    condition     = can(regex("^[A-Za-z0-9 _.:/=+@-]{1,128}$", var.kms_protection_tag_key)) && !startswith(var.kms_protection_tag_key, "aws:")
    error_message = "kms_protection_tag_key must be a valid AWS tag key (1-128 chars, not starting with aws:)."
  }
}

# -----------------------------------------------------------------------------
# Data perimeter (RCP) + declarative EC2 inputs
# -----------------------------------------------------------------------------

variable "data_perimeter_trusted_account_ids" {
  description = "Optional 12-digit account IDs OUTSIDE the organization that are trusted by the RCP data perimeter: their principals (aws:PrincipalAccount) may access org resources, and AWS service calls on their behalf (aws:SourceAccount) pass the confused-deputy check. Empty (default) trusts only the organization. Individual resources can also opt out with the dp:exclude:identity / dp:exclude:source = \"true\" resource tags."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.data_perimeter_trusted_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "data_perimeter_trusted_account_ids entries must be 12-digit AWS account IDs."
  }
}

variable "allow_vpc_bpa_exclusions" {
  description = "Whether member accounts may create VPC Block Public Access exclusions under the declarative EC2 policy. Default false (exclusions_allowed = disabled) so a member-account admin cannot exempt a VPC from the org-wide internet-gateway ingress block."
  type        = bool
  default     = false
}

variable "default_region" {
  description = "Region used by the backup policy's default plan."
  type        = string
  default     = "eu-west-2"
}

# -----------------------------------------------------------------------------
# Policy set + attachments
# -----------------------------------------------------------------------------

variable "policies" {
  description = "Override map of policies to create, keyed by policy name. When empty (default), the module computes the built-in guardrail set from the templated JSON files. Content is a raw Organizations policy JSON string."
  type = map(object({
    type    = string
    content = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for p in values(var.policies) : contains(
        ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "DECLARATIVE_POLICY_EC2", "TAG_POLICY", "BACKUP_POLICY", "AISERVICES_OPT_OUT_POLICY", "CHATBOT_POLICY", "SECURITYHUB_POLICY"],
        p.type
      )
    ])
    error_message = "Each policy type must be a valid AWS Organizations policy type."
  }
}

variable "attachments" {
  description = "Policy attachments binding a policy_key (name in the effective policy set) to a target OU root/OU/account ID. Keyed by a stable caller-chosen string so for_each stays known at plan time even when target_id is a computed root/OU ID."
  type = map(object({
    policy_key = string
    target_id  = string
  }))
  default = {}
}
