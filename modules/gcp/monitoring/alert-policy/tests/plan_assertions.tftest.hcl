# Plan assertions for the monitoring/alert-policy module: verify enable_* flags gate
# their alert policies and notification channels are planned for the supplied targets.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id                   = "mock-project"
  notification_email_addresses = ["oncall@example.com"]
}

run "enabled_cpu_alert_and_email_channel_planned" {
  command = plan

  variables {
    enable_high_cpu_alert = true
  }

  assert {
    condition     = length(google_monitoring_alert_policy.high_cpu) == 1
    error_message = "A high-CPU alert policy must be planned when enable_high_cpu_alert = true."
  }

  assert {
    condition     = length(google_monitoring_notification_channel.email) == 1
    error_message = "An email notification channel must be planned per supplied address."
  }
}

run "disabled_cpu_alert_not_planned" {
  command = plan

  variables {
    enable_high_cpu_alert = false
  }

  assert {
    condition     = length(google_monitoring_alert_policy.high_cpu) == 0
    error_message = "No high-CPU alert policy must be planned when the flag is false."
  }
}
