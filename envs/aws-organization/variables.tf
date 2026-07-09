# -----------------------------------------------------------------------------
# Terraform Cloud
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Provider region (management account)
# -----------------------------------------------------------------------------

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

variable "aws_enabled_regions" {
  description = "Regions this root manages resources in. Defaults to the primary region only; extend for multi-region roots."
  type        = list(string)
  default     = ["eu-west-2"]
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
