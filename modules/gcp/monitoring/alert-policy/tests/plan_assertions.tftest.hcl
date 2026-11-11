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

run "network_data_plane_alerts_off_by_default" {
  command = plan

  assert {
    condition = (
      length(google_monitoring_alert_policy.vpn_tunnel_down) == 0 &&
      length(google_monitoring_alert_policy.bgp_session_down) == 0 &&
      length(google_monitoring_alert_policy.nat_allocation_failed) == 0 &&
      length(google_monitoring_alert_policy.nat_dropped_packets) == 0
    )
    error_message = "The VPN, BGP and Cloud NAT alerts must be opt-in (off by default)."
  }
}

run "network_data_plane_alerts_use_the_right_metrics" {
  command = plan

  variables {
    enable_high_cpu_alert               = false
    enable_high_memory_alert            = false
    enable_error_rate_alert             = false
    enable_high_latency_alert           = false
    enable_vpn_tunnel_alert             = true
    enable_bgp_session_alert            = true
    enable_nat_allocation_failure_alert = true
    enable_nat_dropped_packets_alert    = true
    nat_dropped_packets_threshold       = 10
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.vpn_tunnel_down[0].conditions[0].condition_threshold[0].filter, "vpn.googleapis.com/tunnel_established") &&
      google_monitoring_alert_policy.vpn_tunnel_down[0].conditions[0].condition_threshold[0].comparison == "COMPARISON_LT" &&
      google_monitoring_alert_policy.vpn_tunnel_down[0].conditions[0].condition_threshold[0].threshold_value == 1
    )
    error_message = "The VPN alert must fire when tunnel_established drops below 1."
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.bgp_session_down[0].conditions[0].condition_threshold[0].filter, "router.googleapis.com/bgp/session_up") &&
      strcontains(google_monitoring_alert_policy.bgp_session_down[0].conditions[0].condition_threshold[0].filter, "gce_router")
    )
    error_message = "The BGP alert must watch router.googleapis.com/bgp/session_up on gce_router."
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.nat_allocation_failed[0].conditions[0].condition_threshold[0].filter, "router.googleapis.com/nat/nat_allocation_failed") &&
      google_monitoring_alert_policy.nat_allocation_failed[0].conditions[0].condition_threshold[0].aggregations[0].per_series_aligner == "ALIGN_COUNT_TRUE"
    )
    error_message = "The NAT allocation alert must count true samples of nat_allocation_failed."
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.nat_dropped_packets[0].conditions[0].condition_threshold[0].filter, "router.googleapis.com/nat/dropped_sent_packets_count") &&
      strcontains(google_monitoring_alert_policy.nat_dropped_packets[0].conditions[0].condition_threshold[0].filter, "OUT_OF_RESOURCES") &&
      google_monitoring_alert_policy.nat_dropped_packets[0].conditions[0].condition_threshold[0].threshold_value == 10
    )
    error_message = "The NAT drop alert must watch OUT_OF_RESOURCES drops against nat_dropped_packets_threshold."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.vpn_tunnel_down[0].notification_channels) == 1
    error_message = "The network alerts must notify the module's channels."
  }
}
