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
  description = "Account-qualified exact ARN of the Terraform Cloud run role. Exempt from the baseline SCP's own deny statements where the pipeline must act (never from the tamper denies or the region restriction)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-us-gov|-cn)?:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.terraform_run_role_arn))
    error_message = "terraform_run_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/<name>) with no wildcards (* or ?)."
  }
}

variable "break_glass_role_arn" {
  description = "Account-qualified exact ARN of the emergency break-glass role. Carved out of every deny statement."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-us-gov|-cn)?:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/<name>) with no wildcards (* or ?)."
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
  description = "Names or name patterns (optionally path-prefixed, e.g. \"automation/tfc-apply\" or \"stacksets-exec-*\") of the member-account Terraform pipeline roles. Rendered as arn:aws:iam::*:role/<name> and exempted from the deny-tamper reconfiguration statements (Config recorders, GuardDuty/CloudTrail settings, flow logs, log-archive Object Lock). These roles are also protected from IAM modification, and are NEVER exempt from that protection (see stackset_managed_role_names). NOT exempt from the destructive statements (break-glass only)."
  type        = list(string)
  default     = ["tfc-apply", "OrganizationAccountAccessRole", "stacksets-exec-*"]

  validation {
    condition     = length(var.pipeline_role_names) > 0 && alltrue([for n in var.pipeline_role_names : can(regex("^[A-Za-z0-9+=,.@_/*-]{1,512}$", n)) && !can(regex("^[*/]*$", n))])
    error_message = "pipeline_role_names must be a non-empty list of IAM role names or name patterns (optionally path-prefixed, e.g. stacksets-exec-*); a bare \"*\" is not allowed."
  }
}

variable "central_detection_account_ids" {
  description = "Account IDs that manage detection centrally: the security-tooling delegated admin, plus the log-archive account if it owns a trail. With any set, GuardDuty filter/detector updates, CloudTrail event/insight selector and trail updates, and Security Hub standard disabling are denied to EVERY principal outside these accounts except break-glass, the pipeline included. Empty (default) keeps the pipeline-wide exemption."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.central_detection_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "central_detection_account_ids entries must be 12-digit AWS account IDs."
  }
}

variable "stackset_managed_role_names" {
  description = "Member-account role names (optionally path-prefixed) that a service-managed StackSet owns — by default the tfc-oidc-baseline tfc-plan / tfc-apply roles. Together with the break-glass role name they are protected by DenyStackSetRoleTampering, whose only exemptions are break-glass and stackset_execution_role_names. Every other pipeline_role_names entry (OrganizationAccountAccessRole, stacksets-exec-*) is protected break-glass-only. The pipeline roles are never exempt from either statement."
  type        = list(string)
  default     = ["tfc-plan", "tfc-apply"]

  validation {
    condition     = alltrue([for n in var.stackset_managed_role_names : can(regex("^[A-Za-z0-9+=,.@_/-]{1,512}$", n))])
    error_message = "stackset_managed_role_names entries must be IAM role names without wildcards (optionally path-prefixed)."
  }
}

variable "stackset_execution_role_names" {
  description = "Name patterns of the service-managed StackSet execution role in member accounts (AWS creates stacksets-exec-<hash>). Exempt from DenyStackSetRoleTampering ONLY (so the StackSets can create/update the tfc-* and member break-glass roles); themselves protected break-glass-only by DenyPrivilegedRoleTampering."
  type        = list(string)
  default     = ["stacksets-exec-*"]

  validation {
    condition     = length(var.stackset_execution_role_names) > 0 && alltrue([for n in var.stackset_execution_role_names : can(regex("^[A-Za-z0-9+=,.@_/*-]{1,512}$", n)) && !can(regex("^[*/]*$", n))])
    error_message = "stackset_execution_role_names must be a non-empty list of IAM role names or name patterns; a bare \"*\" is not allowed."
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
  description = "Resource-tag key marking KMS keys protected by the deny-tamper SCP. Keys tagged <key> = \"true\" cannot be scheduled for deletion, disabled, have rotation disabled or the tag removed except by break-glass; their key policy can only be changed by break-glass (so Terraform key-policy changes to protected keys need a break-glass apply). Must match the tag the aws/data/kms-key module applies (protection_tag_key)."
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
  description = "Optional 12-digit account IDs OUTSIDE the organization that are trusted by the RCP data perimeter: their principals (aws:PrincipalAccount) may access org resources, and AWS service calls on their behalf (aws:SourceAccount) pass the confused-deputy check. Empty (default) trusts only the organization. Individual resources can also opt out with the dp:exclude:identity / dp:exclude:source = \"true\" resource tags; the baseline SCP lets only break-glass set or remove dp:* tags."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.data_perimeter_trusted_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "data_perimeter_trusted_account_ids entries must be 12-digit AWS account IDs."
  }
}

variable "federation_tenant_pins" {
  description = "Pin OIDC web-identity federation to YOUR tenants on shared issuers (RCP, every account). With tfc_organization set, sts:AssumeRoleWithWebIdentity with a <tfc_hostname> token is denied unless sub starts organization:<tfc_organization>:. With github_owners set, a GitHub Actions token is denied unless sub is repo:<owner>/*. This stops a pipeline from creating a role that trusts another TFC org or GitHub owner on the same issuer. Tokens from other issuers are unaffected (Null guard)."
  type = object({
    tfc_hostname     = optional(string, "app.terraform.io")
    tfc_organization = optional(string)
    github_owners    = optional(list(string), [])
    # Immutable owner IDs, for deploy roles that use GitHub's customised
    # repository_owner_id:<id>:repository_id:<id>:... subject.
    github_owner_ids = optional(list(string), [])
    # Built-in web-identity providers (no IAM provider resource needed) that
    # roles may trust: any of cognito-identity.amazonaws.com,
    # accounts.google.com, graph.facebook.com, www.amazon.com. Default none.
    allowed_builtin_providers = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.federation_tenant_pins.tfc_organization == null || can(regex("^[A-Za-z0-9_-]+$", coalesce(var.federation_tenant_pins.tfc_organization, "x")))
    error_message = "federation_tenant_pins.tfc_organization must be a literal TFC organization name (letters, digits, - and _; no wildcards)."
  }

  validation {
    condition     = alltrue([for o in var.federation_tenant_pins.github_owners : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", o))])
    error_message = "federation_tenant_pins.github_owners entries must be literal GitHub user/org names (no wildcards or slashes)."
  }

  validation {
    condition     = alltrue([for i in var.federation_tenant_pins.github_owner_ids : can(regex("^[0-9]+$", i))])
    error_message = "federation_tenant_pins.github_owner_ids entries must be numeric GitHub owner IDs."
  }

  validation {
    condition     = alltrue([for p in var.federation_tenant_pins.allowed_builtin_providers : contains(["cognito-identity.amazonaws.com", "accounts.google.com", "graph.facebook.com", "www.amazon.com"], p)])
    error_message = "federation_tenant_pins.allowed_builtin_providers entries must be cognito-identity.amazonaws.com, accounts.google.com, graph.facebook.com or www.amazon.com."
  }

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.federation_tenant_pins.tfc_hostname))
    error_message = "federation_tenant_pins.tfc_hostname must be a bare hostname such as app.terraform.io."
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
      for p in values(var.policies) : can(regex("^[A-Z][A-Z0-9_]*_POLICY(_[A-Z0-9]+)?$", p.type))
    ])
    error_message = "Each policy type must be a valid AWS Organizations policy type."
  }
}

variable "policy_overrides" {
  description = "Policies merged OVER the built-in set, keyed by policy name: an existing key (e.g. scp-region-restriction) replaces that policy's content, a new key adds a policy. Attach additions through attachments. Content is raw Organizations policy JSON."
  type = map(object({
    type    = string
    content = string
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for p in values(var.policy_overrides) : can(regex("^[A-Z][A-Z0-9_]*_POLICY(_[A-Z0-9]+)?$", p.type))])
    error_message = "policy_overrides types must be AWS Organizations policy types such as SERVICE_CONTROL_POLICY."
  }
}

variable "disabled_policies" {
  description = "Built-in policy keys NOT to create (e.g. backup-policy when the backup stage owns it, or aiservices-opt-out). Their attachments must be removed too. A key may not be both disabled and overridden."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(setintersection(toset(var.disabled_policies), toset(keys(var.policy_overrides)))) == 0
    error_message = "A policy key is in both disabled_policies and policy_overrides: an override would silently re-create the disabled policy. Use one or the other."
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

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "partition" {
  description = "AWS partition the policies are rendered for: aws, aws-us-gov or aws-cn. Every ARN in the SCPs / backup policy uses it."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "aws-us-gov", "aws-cn"], var.partition)
    error_message = "partition must be aws, aws-us-gov or aws-cn."
  }
}

# -----------------------------------------------------------------------------
# Config recorder SCP (after the org-wide recorder migration)
# -----------------------------------------------------------------------------

variable "enable_config_recorder_scp" {
  description = "Move the Config recorder actions (Put/Delete/StopConfigurationRecorder, DeleteDeliveryChannel) from DenyWeakenSecurityServices, where every pipeline role is exempt, to DenyConfigRecorderChanges, whose only exemptions are the StackSet execution role, break-glass and config_recorder_pipeline_role_arns. Default false. Turn it on only after the org-wide recorder StackSet has replaced the Terraform-managed member recorders (docs/runbooks/aws-config-recorder-migration.md)."
  type        = bool
  default     = false
  nullable    = false
}

variable "config_recorder_pipeline_role_arns" {
  description = "Account-qualified pipeline role ARNs exempt from DenyConfigRecorderChanges, e.g. the security-tooling tfc-apply that manages the aggregator recorder. Role ARNs only: a whole account is never exempt. Used only when enable_config_recorder_scp = true."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.config_recorder_pipeline_role_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a))])
    error_message = "config_recorder_pipeline_role_arns entries must be account-qualified IAM role ARNs without wildcards."
  }
}
