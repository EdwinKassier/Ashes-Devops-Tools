variable "slack_webhook_url" {
  description = "Slack incoming webhook URL (it embeds a token). Pass it via TF_VAR_slack_webhook_url or a sensitive Terraform Cloud variable."
  type        = string
  sensitive   = true
}
