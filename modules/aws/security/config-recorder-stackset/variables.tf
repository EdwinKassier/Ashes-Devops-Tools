# Required variables

variable "target_ou_ids" {
  description = "OU IDs (or the organization root ID) whose accounts get the recorder. Every account under them except security_tooling_account_id is targeted, and accounts that later join them are auto-deployed. Changing this list forces replacement of the stack instances."
  type        = list(string)

  validation {
    condition     = length(var.target_ou_ids) > 0 && alltrue([for id in var.target_ou_ids : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32})$", id))])
    error_message = "target_ou_ids must be a non-empty list of OU IDs (ou-xxxx-xxxxxxxx) or the root ID (r-xxxx)."
  }
}

variable "security_tooling_account_id" {
  description = "12-digit ID of the security-tooling account, excluded from the StackSet (DIFFERENCE filter): it keeps its own aggregator recorder. Changing it forces replacement of the stack instances."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive S3 bucket the delivery channels write to (aws.log_archive_bucket_name). Its bucket policy, owned by aws-security, must allow AWS Config delivery from the organization."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

# Optional variables

variable "aws_enabled_regions" {
  description = "Regions that get a recorder (one stack instance set per Region)."
  type        = list(string)
  default     = ["eu-west-2"]
  nullable    = false

  validation {
    condition     = length(var.aws_enabled_regions) > 0 && length(var.aws_enabled_regions) == length(distinct(var.aws_enabled_regions))
    error_message = "aws_enabled_regions must be a non-empty list without duplicates."
  }
}

variable "home_region" {
  description = "The only Region whose recorder records global resource types (IAM), so global items are not duplicated per Region. Must be one of aws_enabled_regions."
  type        = string
  default     = "eu-west-2"
  nullable    = false

  validation {
    condition     = contains(var.aws_enabled_regions, var.home_region)
    error_message = "home_region must be one of aws_enabled_regions, or no recorder records global resource types."
  }
}

variable "migration_failure_tolerance_percentage" {
  description = "Percentage of accounts per Region in which a stack operation may fail without failing the whole operation (operation_preferences.failure_tolerance_percentage). 0 (default) for routine runs; the migration pass sets 100 while legacy recorders still block some accounts, then returns to 0."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.migration_failure_tolerance_percentage >= 0 && var.migration_failure_tolerance_percentage <= 100 && floor(var.migration_failure_tolerance_percentage) == var.migration_failure_tolerance_percentage
    error_message = "migration_failure_tolerance_percentage must be a whole number from 0 to 100."
  }
}

variable "max_concurrent_percentage" {
  description = "Maximum percentage of accounts per Region a stack operation runs in at once."
  type        = number
  default     = 25
  nullable    = false

  validation {
    condition     = var.max_concurrent_percentage >= 1 && var.max_concurrent_percentage <= 100 && floor(var.max_concurrent_percentage) == var.max_concurrent_percentage
    error_message = "max_concurrent_percentage must be a whole number from 1 to 100."
  }
}

variable "stack_set_name" {
  description = "Name of the recorder StackSet."
  type        = string
  default     = "org-config-recorders"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,127}$", var.stack_set_name))
    error_message = "stack_set_name must start with a letter and hold only letters, digits and hyphens (max 128)."
  }
}

variable "recorder_name" {
  description = "Name of the configuration recorder in each account and Region."
  type        = string
  default     = "org-recorder"
}

variable "delivery_channel_name" {
  description = "Name of the delivery channel in each account and Region."
  type        = string
  default     = "org-delivery"
}

variable "call_as" {
  description = "Manage the StackSet as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED_ADMIN)."
  type        = string
  default     = "SELF"

  validation {
    condition     = contains(["SELF", "DELEGATED_ADMIN"], var.call_as)
    error_message = "call_as must be SELF or DELEGATED_ADMIN."
  }
}

variable "tags" {
  description = "Tags applied to the StackSet. Org-wide tags come from the root provider's default_tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
