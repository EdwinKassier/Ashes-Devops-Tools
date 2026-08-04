# Example: ops alerting for a production Cloud Run service.
# Creates email + Slack notification channels and enables all default alert policies
# (CPU, memory, 5xx error rate, P99 latency) plus a log-based alert for org-policy
# violations.

module "alerts" {
  source = "../../"

  project_id = "my-workload-project"

  notification_email_addresses = [
    "ops-team@example.com",
    "on-call@example.com",
  ]

  notification_webhook_urls = {
    # Replace with your real Slack incoming webhook URL.
    "slack-ops-channel" = "https://hooks.slack.com/services/T00000000/B00000000/xxxx"
  }

  # Thresholds — tune to match your service SLOs.
  cpu_utilization_threshold    = 0.75 # 75% CPU
  memory_utilization_threshold = 0.85 # 85% memory
  error_rate_threshold_percent = 0.05 # 0.05 req/s of 5xx errors
  latency_p99_threshold_ms     = 1500 # 1.5 s P99 latency

  # Log-based alert fires when a GCP org policy is violated.
  enable_log_based_alert = true
  log_filter             = "severity>=WARNING AND protoPayload.serviceName=\"orgpolicy.googleapis.com\""
  log_alert_display_name = "Org Policy Violation"

  alert_display_name_prefix = "prod"
}
