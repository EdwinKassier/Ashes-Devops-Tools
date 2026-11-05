mock_provider "google" {}

variables {
  project_id                   = "acme-audit-abcd"
  notification_email_addresses = ["secops@acme.test"]
}

run "default_watches_cover_the_control_plane" {
  command = plan

  # One alert policy per default watch (8 guardrail watches).
  assert {
    condition     = length(google_monitoring_alert_policy.watch) == 8
    error_message = "the default watch set must create one alert policy per guardrail (8)."
  }

  # Each default guardrail is present.
  assert {
    condition = alltrue([
      for k in ["org_policy_change", "org_iam_change", "vpc_sc_change", "audit_config_change", "log_sink_change", "custom_role_change", "deny_policy_change", "kms_key_destroy"] :
      contains(keys(google_monitoring_alert_policy.watch), k)
    ])
    error_message = "the default watches must include org policy, org/folder IAM, VPC-SC, audit config, and log sink changes."
  }

  # The org-policy watch is a log-match alert on the orgpolicy service.
  assert {
    condition     = can(regex("orgpolicy.googleapis.com", google_monitoring_alert_policy.watch["org_policy_change"].conditions[0].condition_matched_log[0].filter))
    error_message = "the org-policy watch must match orgpolicy.googleapis.com audit logs."
  }

  # The export-error alert is on by default.
  assert {
    condition     = length(google_monitoring_alert_policy.log_export_error) == 1
    error_message = "the audit-sink export-error alert must be created by default."
  }

  # An email channel was created.
  assert {
    condition     = length(google_monitoring_notification_channel.email) == 1
    error_message = "an email notification channel must be created for the provided address."
  }
}

run "master_gate_disables_everything" {
  command = plan

  variables {
    enable = false
  }

  assert {
    condition     = length(google_monitoring_alert_policy.watch) == 0 && length(google_monitoring_alert_policy.log_export_error) == 0 && length(google_monitoring_notification_channel.email) == 0
    error_message = "enable = false must create no channels and no alert policies."
  }
}

run "admin_can_replace_the_watch_set" {
  command = plan

  variables {
    watches = {
      billing_change = {
        display_name = "Billing account unlinked"
        filter       = "protoPayload.methodName=\"UpdateProjectBillingInfo\""
        severity     = "CRITICAL"
      }
    }
    enable_log_export_error_alert = false
  }

  assert {
    condition     = length(google_monitoring_alert_policy.watch) == 1 && contains(keys(google_monitoring_alert_policy.watch), "billing_change")
    error_message = "admins must be able to replace the default watch set with their own."
  }
}

run "no_org_route_or_break_glass_watch_by_default" {
  command = plan

  assert {
    condition     = length(google_logging_organization_sink.control_plane) == 0 && !contains(keys(google_monitoring_alert_policy.watch), "break_glass_use")
    error_message = "without org_id / break_glass_principal_emails there must be no org route sink and no break-glass watch."
  }
}

run "break_glass_watch_and_org_route" {
  command = plan

  variables {
    org_id                       = "123456789012"
    break_glass_principal_emails = ["bg-1@acme.test", "bg-2@acme.test"]
  }

  assert {
    condition     = google_monitoring_alert_policy.watch["break_glass_use"].severity == "CRITICAL"
    error_message = "the break-glass watch must be CRITICAL."
  }

  assert {
    condition = alltrue([
      for e in ["bg-1@acme.test", "bg-2@acme.test"] :
      strcontains(google_monitoring_alert_policy.watch["break_glass_use"].conditions[0].condition_matched_log[0].filter, "principalEmail=\"${e}\"")
    ])
    error_message = "the break-glass watch filter must match every break-glass principal."
  }

  assert {
    condition     = google_logging_organization_sink.control_plane[0].destination == "logging.googleapis.com/projects/acme-audit-abcd"
    error_message = "the org route sink must deliver into the monitoring project."
  }

  assert {
    condition     = google_logging_organization_sink.control_plane[0].include_children == true && strcontains(google_logging_organization_sink.control_plane[0].filter, "cloudaudit.googleapis.com%2Factivity")
    error_message = "the org route sink must include children and route Admin Activity audit logs."
  }

  assert {
    condition     = google_project_iam_member.control_plane_sink_writer[0].role == "roles/logging.logWriter"
    error_message = "the route sink writer identity must get logging.logWriter on the monitoring project."
  }
}
