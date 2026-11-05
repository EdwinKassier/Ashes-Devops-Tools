mock_provider "google" {}

variables {
  project_id          = "my-project"
  service_id          = "svc-123"
  slo_id              = "api-availability"
  display_name        = "API 99.9% availability"
  goal                = 0.999
  rolling_period_days = 28
}

run "availability_slo_no_alert_by_default" {
  command = plan

  assert {
    condition     = google_monitoring_slo.this.goal == 0.999 && google_monitoring_slo.this.rolling_period_days == 28
    error_message = "SLO goal and rolling period must be wired through."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.burn_rate) == 0
    error_message = "the burn-rate alert must be off by default."
  }
}

run "burn_rate_alert_when_enabled" {
  command = plan

  variables {
    enable_burn_rate_alert = true
    notification_channels  = ["projects/my-project/notificationChannels/1"]
  }

  assert {
    condition     = length(google_monitoring_alert_policy.burn_rate) == 1
    error_message = "enabling the burn-rate alert must create one alert policy."
  }
}
