variable "trail_name" {
  description = "Name of the organization CloudTrail trail."
  type        = string
  default     = "org-trail"

  validation {
    condition     = length(trimspace(var.trail_name)) > 0
    error_message = "trail_name must be a non-empty string."
  }
}

variable "log_archive_bucket" {
  description = "Name of the central Log-Archive S3 bucket that receives the trail's log files. This bucket lives in the Log-Archive account (a different account from the trail owner); its resource policy authorizes CloudTrail delivery."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket)) > 0
    error_message = "log_archive_bucket must be a non-empty S3 bucket name."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the CloudTrail log files delivered to the Log-Archive bucket."
  type        = string

  validation {
    condition     = length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn must be a non-empty KMS key ARN."
  }
}

# --- Data events (CIS AWS 3.8 / 3.9) ---------------------------------------
variable "cloudtrail_s3_data_events" {
  description = "S3 object-level data events recorded by the org trail via advanced event selectors: none, write (CIS AWS 3.8, default), read (CIS 3.9) or all (3.8 + 3.9). COST: data events are billed per event across EVERY org account; read/all on busy buckets can be expensive."
  type        = string
  default     = "write"

  validation {
    condition     = contains(["none", "write", "read", "all"], var.cloudtrail_s3_data_events)
    error_message = "cloudtrail_s3_data_events must be one of: none, write, read, all."
  }
}

variable "exclude_log_archive_bucket_from_data_events" {
  description = "Exclude the log-archive bucket (log_archive_bucket) from S3 data events so CloudTrail does not record its own log deliveries (a self-amplifying loop). Default true."
  type        = bool
  default     = true
}

variable "s3_data_events_excluded_bucket_arns" {
  description = "Additional S3 bucket ARNs (arn:aws:s3:::name) excluded from S3 data events, e.g. high-volume access-log or Security Lake buckets. Matched as a resources.ARN NotStartsWith prefix."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for b in var.s3_data_events_excluded_bucket_arns : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/?$", b))])
    error_message = "s3_data_events_excluded_bucket_arns entries must be S3 bucket ARNs of the form arn:aws:s3:::bucket-name."
  }
}

variable "enable_lambda_data_events" {
  description = "Record Lambda Invoke data events (AWS::Lambda::Function) on the org trail. Default false — per-invocation billing can be significant for high-throughput functions."
  type        = bool
  default     = false
}

# --- CloudWatch Logs + CIS section-4 alarms ----------------------------------
variable "enable_cloudwatch_logs" {
  description = "Attach a CloudWatch Logs group to the org trail and create the CIS AWS section-4 metric-filter alarms (4.1-4.15) with a KMS-encrypted SNS topic. Self-sufficient by default: a logs-granted CMK is created when cloudwatch_logs_kms_key_arn is null. Set false for S3-only delivery."
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "Retention (days) for the CloudWatch Logs group when enable_cloudwatch_logs = true. The S3 log archive remains the long-term record."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_logs_retention_days)
    error_message = "cloudwatch_logs_retention_days must be a CloudWatch Logs supported retention value (e.g. 90, 365, 731)."
  }
}

variable "cloudwatch_logs_kms_key_arn" {
  description = "Optional existing CMK ARN for the CloudWatch Logs group AND the CIS alarm SNS topic. Its key policy MUST grant logs.<region>.amazonaws.com (encryption context arn:aws:logs:<region>:<account>:log-group:*) and cloudwatch.amazonaws.com (kms:Decrypt, kms:GenerateDataKey*). Null (default) = the module creates a dedicated, rotated CMK with exactly those grants."
  type        = string
  default     = null

  validation {
    condition     = var.cloudwatch_logs_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.cloudwatch_logs_kms_key_arn))
    error_message = "cloudwatch_logs_kms_key_arn must be null or a KMS key ARN."
  }
}

variable "cloudwatch_logs_kms_key_admin_arn" {
  description = "Principal granted administration of the module-created CloudWatch Logs CMK. Null (default) = the trail account's root (delegates to IAM policies, the AWS default key policy) so the key cannot be orphaned."
  type        = string
  default     = null
}

variable "cloudwatch_logs_kms_key_manager_arns" {
  description = "IAM role ARNs (the pipeline role that applies this module) granted day-2 management of the module-created CloudWatch Logs CMK by key policy: describe/get/list, rotation, description, tags and aliases. No PutKeyPolicy, grants, disable or deletion. The account-root administration statement is always kept. Empty (default) = no pipeline statement."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.cloudwatch_logs_kms_key_manager_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", a))])
    error_message = "cloudwatch_logs_kms_key_manager_arns entries must be IAM role ARNs (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN for CIS alarm notifications. Null (default) = the module creates a KMS-encrypted topic (<trail_name>-cis-alarms) and subscribes alarm_subscriptions to it."
  type        = string
  default     = null
}

variable "alarm_subscriptions" {
  description = "Subscribers of the module-created CIS alarm SNS topic, keyed by an arbitrary name (ignored when alarm_sns_topic_arn is supplied). Email subscriptions must be confirmed by the recipient."
  type = map(object({
    protocol = string
    endpoint = string
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.alarm_subscriptions) : contains(["email", "email-json", "https", "sqs", "lambda", "sms", "firehose"], s.protocol)])
    error_message = "alarm_subscriptions protocol must be one of: email, email-json, https, sqs, lambda, sms, firehose."
  }
}

variable "cis_alarms_excluded" {
  description = "Keys of CIS metric-filter alarms to skip (e.g. [\"unauthorized-api-calls\"] if it is too noisy org-wide). Valid keys: unauthorized-api-calls, console-signin-without-mfa, root-account-usage, iam-policy-changes, cloudtrail-config-changes, console-auth-failures, cmk-disable-or-deletion, s3-bucket-policy-changes, config-changes, security-group-changes, nacl-changes, network-gateway-changes, route-table-changes, vpc-changes, organizations-changes."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([for k in var.cis_alarms_excluded : contains([
      "unauthorized-api-calls", "console-signin-without-mfa", "root-account-usage", "iam-policy-changes",
      "cloudtrail-config-changes", "console-auth-failures", "cmk-disable-or-deletion", "s3-bucket-policy-changes",
      "config-changes", "security-group-changes", "nacl-changes", "network-gateway-changes",
      "route-table-changes", "vpc-changes", "organizations-changes",
    ], k)])
    error_message = "cis_alarms_excluded entries must be valid CIS alarm keys (see the variable description)."
  }
}

variable "cis_metric_namespace" {
  description = "CloudWatch metric namespace for the CIS metric filters."
  type        = string
  default     = "CISBenchmark"
}

variable "tags" {
  description = "Tags applied to the module's taggable resources (CMK, log group, IAM role, SNS topic, alarms)."
  type        = map(string)
  default     = {}
}

variable "cloudwatch_logs_role_arn" {
  description = "ARN of an existing role CloudTrail assumes to deliver to the CloudWatch Logs group (/aws/cloudtrail/<trail_name>). Null = this module creates <trail_name>-cloudwatch-delivery. The landing zone passes the role aws-organization creates, so the aws-security pipeline role needs no IAM write permissions."
  type        = string
  default     = null

  validation {
    condition     = var.cloudwatch_logs_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.cloudwatch_logs_role_arn, "x")))
    error_message = "cloudwatch_logs_role_arn must be null or an IAM role ARN."
  }
}

variable "trail_owner_account_id" {
  description = "Account that owns the trail when it differs from the provider's account: the management account, for an organization trail created by a CloudTrail delegated administrator. The module-created CloudWatch Logs delivery role then trusts cloudtrail.amazonaws.com with aws:SourceAccount set to either account. Null = the provider's account only."
  type        = string
  default     = null

  validation {
    condition     = var.trail_owner_account_id == null || can(regex("^[0-9]{12}$", coalesce(var.trail_owner_account_id, "x")))
    error_message = "trail_owner_account_id must be null or a 12-digit account ID."
  }
}

variable "cloudwatch_logs_role_permissions_boundary_arn" {
  description = "Permissions boundary for the module-created CloudWatch Logs delivery role (when cloudwatch_logs_role_arn is null). Required in a member account whose pipeline role may only create bounded roles. Null = no boundary."
  type        = string
  default     = null

  validation {
    condition     = var.cloudwatch_logs_role_permissions_boundary_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/.+$", coalesce(var.cloudwatch_logs_role_permissions_boundary_arn, "x")))
    error_message = "cloudwatch_logs_role_permissions_boundary_arn must be null or an IAM policy ARN."
  }
}
