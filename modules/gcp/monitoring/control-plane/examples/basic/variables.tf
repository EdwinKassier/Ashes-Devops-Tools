variable "notification_webhook_urls" {
  description = "Optional map of label to webhook URL (e.g. Slack). Set it with TF_VAR_notification_webhook_urls or a TFC sensitive variable."
  type        = map(string)
  default     = {}
  sensitive   = true
}
