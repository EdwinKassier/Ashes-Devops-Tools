variable "enable_service_quotas" {
  description = "Master switch for service-quota management. Opt-in: when false (the default), no quota requests or usage alarms are created."
  type        = bool
  default     = false
}

variable "quota_increases" {
  description = "Map of quota-increase requests keyed by an arbitrary name. Each entry files a service-quota request and provisions an AWS/Usage alarm at ~80% of the requested value."
  type = map(object({
    service_code = string # e.g. "ec2"
    quota_code   = string # e.g. "L-1216C47A"
    value        = number # requested quota value
  }))
  default = {}
}

variable "notifications_topic_arn" {
  description = "ARN of the SNS topic (from the security-notifications module) that usage alarms route to. When empty, alarms are created with no actions."
  type        = string
  default     = ""
}
