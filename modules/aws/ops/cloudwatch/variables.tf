variable "name_prefix" {
  description = "Prefix applied to created resource names (SNS topic, dashboard) and used to namespace alarms."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,48}$", var.name_prefix))
    error_message = "name_prefix must be 1-48 chars of letters, digits, or hyphens."
  }
}

variable "alarms" {
  description = "Map of CloudWatch metric alarms to create, keyed by alarm name. The parity counterpart to GCP's monitoring/alert-policy."
  type = map(object({
    namespace           = string
    metric_name         = string
    statistic           = optional(string, "Average")
    comparison_operator = string
    threshold           = number
    period              = optional(number, 300)
    evaluation_periods  = optional(number, 1)
    datapoints_to_alarm = optional(number)
    dimensions          = optional(map(string), {})
    treat_missing_data  = optional(string, "notBreaching")
    alarm_description   = optional(string)
    unit                = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.alarms) : contains([
        "GreaterThanOrEqualToThreshold", "GreaterThanThreshold",
        "LessThanThreshold", "LessThanOrEqualToThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold", "LessThanLowerThreshold", "GreaterThanUpperThreshold"
      ], a.comparison_operator)
    ])
    error_message = "Each alarm comparison_operator must be a valid CloudWatch comparison operator."
  }

  validation {
    condition = alltrue([
      for a in values(var.alarms) : contains(["SampleCount", "Average", "Sum", "Minimum", "Maximum"], a.statistic)
    ])
    error_message = "Each alarm statistic must be one of SampleCount, Average, Sum, Minimum, Maximum."
  }

  validation {
    condition     = alltrue([for a in values(var.alarms) : a.period > 0])
    error_message = "Each alarm period must be greater than 0 seconds."
  }

  validation {
    condition = alltrue([
      for a in values(var.alarms) : contains(["missing", "ignore", "breaching", "notBreaching"], a.treat_missing_data)
    ])
    error_message = "Each alarm treat_missing_data must be one of missing, ignore, breaching, notBreaching."
  }
}

variable "create_sns_topic" {
  description = "Create an SNS topic and wire it as the alarm/OK action for every alarm. When false, supply sns_topic_arn to reuse an existing topic (or leave null for no notifications)."
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "Existing SNS topic ARN to use for alarm/OK actions when create_sns_topic = false. Null = no notification actions."
  type        = string
  default     = null
}

variable "sns_kms_master_key_id" {
  description = "KMS key id/alias for encrypting the created SNS topic (only used when create_sns_topic = true). Null = AWS-managed key."
  type        = string
  default     = null
}

variable "enable_dashboard" {
  description = "Create a CloudWatch dashboard from dashboard_widgets. The parity counterpart to GCP's monitoring/compute-dashboard."
  type        = bool
  default     = false
}

variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard (defaults to \"<name_prefix>-dashboard\" when null)."
  type        = string
  default     = null
}

variable "dashboard_widgets" {
  description = "List of CloudWatch dashboard widget objects (rendered into the dashboard body via jsonencode). Empty = a minimal single-text-widget placeholder."
  type        = list(any)
  default     = []
}

variable "tags" {
  description = "Tags applied to taggable resources (SNS topic)."
  type        = map(string)
  default     = {}
}
