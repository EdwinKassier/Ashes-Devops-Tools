# Example: landing-zone control-plane alerting in the org audit-logs project.
# An aggregated org sink routes Admin Activity and Policy audit logs into the
# project, and the default watches alert on guardrail changes (org policy,
# org/folder IAM, VPC-SC, audit config, log sinks, KMS, deny policies, ...),
# plus the CIS 2.4-2.11 log-based metrics and a watch on any break-glass use.
#
# Notifications go to a SecOps mailbox and, optionally, Slack webhooks. Webhook
# URLs can embed tokens, so they come from a sensitive variable
# (TF_VAR_notification_webhook_urls or a TFC sensitive variable); never commit them.
# Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "control_plane_alerts" {
  source = "../../"

  project_id = "my-audit-logs-project"
  org_id     = "123456789012"

  notification_email_addresses = ["secops@example.com"]
  notification_webhook_urls    = var.notification_webhook_urls

  break_glass_principal_emails = ["break-glass-admin@example.com"]

  # Needs the audit sink's logging_sink metric in project_id; set false otherwise.
  enable_log_export_error_alert = true

  # watches and cis_log_metrics keep their full default sets.

  labels = {
    team = "secops"
  }
}
