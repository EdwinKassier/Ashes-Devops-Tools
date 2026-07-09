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
