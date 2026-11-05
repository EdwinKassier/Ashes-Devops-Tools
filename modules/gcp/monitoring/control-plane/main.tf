# Control-plane observability for the landing zone itself (audit M-ops).
#
# Alerts on changes to the guardrails that protect the org: organization policy,
# org/folder IAM, VPC Service Controls, audit-logging config, and logging sinks.
# Also optionally alerts when the audit-log export sink starts failing (a stalled
# audit pipeline). Everything is opt-in: enable=false makes the module a no-op,
# and admins control the watch set and the notification channels.
#
# Apply this in the project that receives the aggregated org Admin Activity audit
# logs (typically the org logging/audit project), so the filters have logs to
# match. Terraform Cloud run-failure alerting lives in modules/tfc/workspace.

locals {
  all_channel_ids = var.enable ? concat(
    [for ch in google_monitoring_notification_channel.email : ch.id],
    [for ch in google_monitoring_notification_channel.webhook : ch.id],
    var.extra_notification_channel_ids,
  ) : []

  # Break-glass use watch: any Admin Activity by a break-glass principal.
  break_glass_watch = length(var.break_glass_principal_emails) == 0 ? {} : {
    break_glass_use = {
      display_name  = "Break-glass principal used"
      filter        = "logName:\"cloudaudit.googleapis.com\" AND (${join(" OR ", [for e in var.break_glass_principal_emails : "protoPayload.authenticationInfo.principalEmail=\"${e}\""])})"
      severity      = "CRITICAL"
      documentation = "A break-glass principal performed an administrative action. Confirm an incident is open and the use was authorised; rotate the credential afterwards."
    }
  }

  active_watches = var.enable ? merge(var.watches, local.break_glass_watch) : {}

  route_org_logs = var.enable && var.org_id != null
}

# Org- and folder-level audit entries (org IAM, org policy, VPC-SC, org sinks,
# deny policies) live in the organization's own log buckets, not in any project,
# so a project-scoped log-match alert never sees them. Route the org's Admin
# Activity + Policy audit logs into project_id (excluding project_id's own logs,
# which are already there) so the watches below can match them.
resource "google_logging_organization_sink" "control_plane" {
  count = local.route_org_logs ? 1 : 0

  name             = var.org_log_route_sink_name
  org_id           = var.org_id
  destination      = "logging.googleapis.com/projects/${var.project_id}"
  include_children = true
  filter           = "(logName:\"cloudaudit.googleapis.com%2Factivity\" OR logName:\"cloudaudit.googleapis.com%2Fpolicy\") AND NOT logName:\"projects/${var.project_id}/\""
  description      = "Routes org Admin Activity/Policy audit logs to the control-plane monitoring project for log-match alerting."
}

# A sink whose destination is another project needs logging.logWriter there.
resource "google_project_iam_member" "control_plane_sink_writer" {
  count = local.route_org_logs ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_logging_organization_sink.control_plane[0].writer_identity
}

resource "google_monitoring_notification_channel" "email" {
  for_each = var.enable ? toset(var.notification_email_addresses) : []

  project      = var.project_id
  display_name = "Control-plane email: ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }
  user_labels  = var.labels
}

resource "google_monitoring_notification_channel" "webhook" {
  # Webhook URLs embed auth tokens, so the map is sensitive and cannot drive
  # for_each directly. Iterate the non-secret keys and look up the URL.
  for_each = var.enable ? nonsensitive(toset(keys(var.notification_webhook_urls))) : []

  project      = var.project_id
  display_name = "Control-plane webhook: ${each.key}"
  type         = "webhook_tokenauth"
  labels       = { url = var.notification_webhook_urls[each.key] }
  user_labels  = var.labels
}

# One log-match alert policy per watch. A matching audit-log entry (a guardrail
# mutation) fires the alert.
resource "google_monitoring_alert_policy" "watch" {
  for_each = local.active_watches

  project      = var.project_id
  display_name = "${var.alert_display_name_prefix}${each.value.display_name}"
  combiner     = "OR"
  severity     = try(each.value.severity, "WARNING")

  conditions {
    display_name = each.value.display_name

    condition_matched_log {
      filter = each.value.filter
    }
  }

  notification_channels = local.all_channel_ids

  alert_strategy {
    notification_rate_limit {
      period = "${var.notification_rate_limit_seconds}s"
    }
  }

  documentation {
    content   = try(each.value.documentation, "A control-plane guardrail changed. Confirm the change was authorised. Filter: `${each.value.filter}`")
    mime_type = "text/markdown"
  }
}

# Optional: alert when the audit-log export sink reports errors (stalled/failing
# audit pipeline).
resource "google_monitoring_alert_policy" "log_export_error" {
  count = var.enable && var.enable_log_export_error_alert ? 1 : 0

  project      = var.project_id
  display_name = "${var.alert_display_name_prefix}Audit log export errors"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "logging exports/error_count > 0"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/exports/error_count\" resource.type=\"logging_sink\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.all_channel_ids

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "The audit-log export sink is reporting delivery errors. The audit pipeline may be stalled: check the sink's destination permissions and existence."
    mime_type = "text/markdown"
  }
}
