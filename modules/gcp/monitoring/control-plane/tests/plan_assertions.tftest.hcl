mock_provider "google" {}

variables {
  project_id                   = "acme-audit-abcd"
  notification_email_addresses = ["secops@acme.test"]
}

run "default_watches_cover_the_control_plane" {
  command = plan

  # One alert policy per default watch (15 guardrail watches).
  assert {
    condition     = length(google_monitoring_alert_policy.watch) == 15
    error_message = "the default watch set must create one alert policy per guardrail (10)."
  }

  # Each default guardrail is present.
  assert {
    condition = alltrue([
      for k in ["org_policy_change", "org_iam_change", "vpc_sc_change", "audit_config_change", "log_sink_change", "custom_role_change", "deny_policy_change", "kms_key_destroy", "kms_key_version_disable", "tag_binding_change", "guardrail_role_grant", "guardrail_identity_change", "principal_access_boundary_change", "log_bucket_or_settings_change", "pam_entitlement_change"] :
      contains(keys(google_monitoring_alert_policy.watch), k)
    ])
    error_message = "the default watches must include org policy, org/folder IAM, VPC-SC, audit config, and log sink changes."
  }

  # Containment bypass paths that IAM deny cannot block are watched instead.
  assert {
    condition     = strcontains(google_monitoring_alert_policy.watch["tag_binding_change"].conditions[0].condition_matched_log[0].filter, "DeleteTagBinding") && strcontains(google_monitoring_alert_policy.watch["kms_key_version_disable"].conditions[0].condition_matched_log[0].filter, "DISABLED")
    error_message = "tag binding deletion and KMS key-version disable must be watched."
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
    condition     = length(google_monitoring_alert_policy.watch) == 0 && length(google_monitoring_alert_policy.log_export_error) == 0 && length(google_monitoring_notification_channel.email) == 0 && length(google_logging_metric.cis) == 0 && length(google_monitoring_alert_policy.cis) == 0
    error_message = "enable = false must create no channels, no alert policies and no CIS metrics."
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

run "cis_log_metrics_cover_2_4_to_2_11" {
  command = plan

  variables {
    org_id = "123456789012"
  }

  assert {
    condition     = length(google_logging_metric.cis) == 8 && length(google_monitoring_alert_policy.cis) == 8
    error_message = "the default CIS set must create 8 log-based metrics (2.4-2.11) and one alert per metric."
  }

  assert {
    condition = alltrue([
      for k in keys(google_logging_metric.cis) :
      google_logging_metric.cis[k].name == "cis-${k}" &&
      google_logging_metric.cis[k].metric_descriptor[0].metric_kind == "DELTA" &&
      google_logging_metric.cis[k].metric_descriptor[0].value_type == "INT64"
    ])
    error_message = "each CIS metric must be a cis-<key> DELTA/INT64 counter."
  }

  # The CIS-documented filters, one assertion per control.
  assert {
    condition     = google_logging_metric.cis["project_ownership_change"].filter == "(protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\") AND (ProjectOwnership OR projectOwnerInvitee) OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"REMOVE\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"ADD\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\")"
    error_message = "CIS 2.4 project-ownership filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["audit_config_change"].filter == "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
    error_message = "CIS 2.5 audit-configuration filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["custom_role_change"].filter == "resource.type=\"iam_role\" AND (protoPayload.methodName=\"google.iam.admin.v1.CreateRole\" OR protoPayload.methodName=\"google.iam.admin.v1.DeleteRole\" OR protoPayload.methodName=\"google.iam.admin.v1.UpdateRole\")"
    error_message = "CIS 2.6 custom-role filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["vpc_firewall_rule_change"].filter == "resource.type=\"gce_firewall_rule\" AND (protoPayload.methodName:\"compute.firewalls.patch\" OR protoPayload.methodName:\"compute.firewalls.insert\" OR protoPayload.methodName:\"compute.firewalls.delete\")"
    error_message = "CIS 2.7 firewall-rule filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["vpc_route_change"].filter == "resource.type=\"gce_route\" AND (protoPayload.methodName:\"compute.routes.delete\" OR protoPayload.methodName:\"compute.routes.insert\")"
    error_message = "CIS 2.8 route filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["vpc_network_change"].filter == "resource.type=\"gce_network\" AND (protoPayload.methodName:\"compute.networks.insert\" OR protoPayload.methodName:\"compute.networks.patch\" OR protoPayload.methodName:\"compute.networks.delete\" OR protoPayload.methodName:\"compute.networks.removePeering\" OR protoPayload.methodName:\"compute.networks.addPeering\")"
    error_message = "CIS 2.9 network filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["storage_iam_change"].filter == "resource.type=\"gcs_bucket\" AND protoPayload.methodName=\"storage.setIamPermissions\""
    error_message = "CIS 2.10 storage-IAM filter mismatch."
  }

  assert {
    condition     = google_logging_metric.cis["sql_instance_config_change"].filter == "protoPayload.methodName=\"cloudsql.instances.update\""
    error_message = "CIS 2.11 Cloud SQL filter mismatch."
  }

  # Each alert watches its own metric and fires on any count > 0.
  assert {
    condition = alltrue([
      for k, p in google_monitoring_alert_policy.cis :
      p.conditions[0].condition_threshold[0].filter == "metric.type=\"logging.googleapis.com/user/cis-${k}\"" &&
      p.conditions[0].condition_threshold[0].comparison == "COMPARISON_GT" &&
      p.conditions[0].condition_threshold[0].threshold_value == 0
    ])
    error_message = "each CIS alert must threshold its own log metric at > 0."
  }

  # One aggregated org sink feeds the metrics: project-level Admin Activity from
  # every child project, not just org/folder entries.
  assert {
    condition = (
      google_logging_organization_sink.control_plane[0].include_children == true &&
      strcontains(google_logging_organization_sink.control_plane[0].filter, "cloudaudit.googleapis.com%2Factivity") &&
      !strcontains(google_logging_organization_sink.control_plane[0].filter, "resource.type")
    )
    error_message = "the org sink must route every child project's Admin Activity (no resource.type restriction) so the CIS metrics cover the org."
  }

  assert {
    condition     = google_monitoring_alert_policy.cis["project_ownership_change"].display_name == "Control plane: CIS 2.4 Project ownership assignment or change"
    error_message = "CIS alert display names must carry the CIS control number."
  }
}

run "cis_log_metrics_can_be_disabled" {
  command = plan

  variables {
    enable_cis_log_metrics = false
  }

  assert {
    condition     = length(google_logging_metric.cis) == 0 && length(google_monitoring_alert_policy.cis) == 0 && length(google_monitoring_alert_policy.watch) == 15
    error_message = "enable_cis_log_metrics = false must drop only the CIS metrics and alerts."
  }
}

# The self-grant of a guardrail-owner role (denyAdmin) by the org apply SA
# cannot be denied, so it must page.
run "guardrail_owner_grant_is_watched" {
  command = plan

  assert {
    condition     = strcontains(google_monitoring_alert_policy.watch["guardrail_role_grant"].conditions[0].condition_matched_log[0].filter, "roles/iam.denyAdmin") && google_monitoring_alert_policy.watch["guardrail_role_grant"].severity == "CRITICAL"
    error_message = "A CRITICAL watch must fire on org/folder grants of roles/iam.denyAdmin."
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.watch["guardrail_identity_change"].conditions[0].condition_matched_log[0].filter, "-guardrails-apply@")
    error_message = "IAM changes on the guardrails SA must be watched."
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.watch["log_bucket_or_settings_change"].conditions[0].condition_matched_log[0].filter, "UpdateSettings") && strcontains(google_monitoring_alert_policy.watch["principal_access_boundary_change"].conditions[0].condition_matched_log[0].filter, "PolicyBindings.Delete")
    error_message = "Log bucket/settings and principal access boundary changes must be watched."
  }
}
