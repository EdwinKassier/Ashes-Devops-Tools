variable "enable_security_notifications" {
  description = "Master switch for the security-notifications detective control. When false, no SNS topic, subscriptions, EventBridge rules, or Security Hub automation rule are created."
  type        = bool
  default     = true
}

variable "topic_name" {
  description = "Name of the KMS-encrypted SNS topic that all security notifications are published to."
  type        = string
  default     = "security-notifications"
}

variable "kms_key_id" {
  description = "KMS key ID or ARN used to encrypt the SNS topic (kms_master_key_id)."
  type        = string
}

variable "notification_subscribers" {
  description = "Map of subscribers to attach to the SNS topic, keyed by an arbitrary name. A subscriber is required when the module is enabled — otherwise findings fire into a void."
  type = map(object({
    protocol = string # "email" | "https" | "sms" | "sqs" | "lambda" | ...
    endpoint = string # e.g. an email address or HTTPS URL
  }))
  default = {}

  validation {
    # When enabled, at least one subscriber is required so notifications have
    # somewhere to go. Empty is only tolerated while the module is disabled.
    condition     = !var.enable_security_notifications || length(var.notification_subscribers) > 0
    error_message = "notification_subscribers must contain at least one subscriber when enable_security_notifications is true."
  }
}

variable "break_glass_role_arn" {
  description = "ARN of the break-glass IAM role to watch for assumption. Any AssumeRole against this ARN raises a notification. The iam-role module defines the role; this module is its detective control."
  type        = string
  default     = ""
}

variable "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch Logs group the organization CloudTrail delivers into. When set (and break_glass_role_arn is set), a metric-filter + CloudWatch metric alarm on break-glass AssumeRole is created there, alarming into the SNS topic. Empty (default) omits the alarm; the always-on EventBridge rule remains the log-group-independent path."
  type        = string
  default     = ""
}

variable "break_glass_metric_namespace" {
  description = "CloudWatch metric namespace for the break-glass metric filter and alarm."
  type        = string
  default     = "SecurityNotifications"
}

variable "automation_rule_name" {
  description = "Name of the Security Hub automation rule that auto-notes informational findings."
  type        = string
  default     = "sec-notify-suppress-informational"
}
