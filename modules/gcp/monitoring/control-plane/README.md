# control-plane

Control-plane observability for the landing zone itself (audit M-ops). Alerts when
the guardrails that protect the organization change, and optionally when the
audit-log export pipeline fails.

## What it watches

Default watches, each a log-match alert on Admin Activity audit logs:

- Organization policy changes (`orgpolicy.googleapis.com`).
- Organization or folder IAM policy changes (`SetIamPolicy`).
- VPC Service Controls perimeter changes (`accesscontextmanager.googleapis.com`).
- Audit logging configuration changes (`auditConfigDeltas`).
- Logging sink updates or deletes.

Plus, optionally, an alert when the audit-log export sink reports delivery errors
(`logging.googleapis.com/exports/error_count`), which signals a stalled audit
pipeline.

Terraform Cloud run-failure alerting (a failed apply) is configured separately on
each workspace via `modules/tfc/workspace`.

## Admin control

- `enable = false` makes the module a no-op.
- `watches` is a map with a full default set. Remove an entry to stop watching it,
  change a `filter`, or add your own watches. Replacing the map replaces the set.
- Channels are yours: `notification_email_addresses`, `notification_webhook_urls`
  (Slack or generic), and `extra_notification_channel_ids` for pre-existing ones.
- `enable_log_export_error_alert` toggles the audit-sink error alert.

## Where to apply it

Apply in the project that receives the aggregated organization Admin Activity audit
logs (usually the org logging or audit project), so the filters have logs to match.

## Usage

```hcl
module "control_plane_alerts" {
  source                       = "../../modules/gcp/monitoring/control-plane"
  project_id                   = local.audit_logs_project_id
  notification_email_addresses = ["secops@example.com"]
  notification_webhook_urls = {
    slack-secops = "https://hooks.slack.com/services/..."
  }
  # watches defaults to the full control-plane set; override to customise.
}
```

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_logging_metric.cis (modules/gcp/monitoring/control-plane/main.tf#L167)
- resource.google_logging_organization_sink.control_plane (modules/gcp/monitoring/control-plane/main.tf#L45)
- resource.google_monitoring_alert_policy.cis (modules/gcp/monitoring/control-plane/main.tf#L183)
- resource.google_monitoring_alert_policy.log_export_error (modules/gcp/monitoring/control-plane/main.tf#L121)
- resource.google_monitoring_alert_policy.watch (modules/gcp/monitoring/control-plane/main.tf#L89)
- resource.google_monitoring_notification_channel.email (modules/gcp/monitoring/control-plane/main.tf#L65)
- resource.google_monitoring_notification_channel.webhook (modules/gcp/monitoring/control-plane/main.tf#L75)
- resource.google_project_iam_member.control_plane_sink_writer (modules/gcp/monitoring/control-plane/main.tf#L57)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project that holds the alert policies and notification channels. Use the project that receives the aggregated org Admin Activity audit logs, so the watch filters have logs to match. | `string` | n/a | yes |
| <a name="input_alert_display_name_prefix"></a> [alert\_display\_name\_prefix](#input\_alert\_display\_name\_prefix) | Prefix prepended to every alert policy display name, e.g. "Control plane: ". | `string` | `"Control plane: "` | no |
| <a name="input_break_glass_principal_emails"></a> [break\_glass\_principal\_emails](#input\_break\_glass\_principal\_emails) | Emails of break-glass principals (users or service accounts). When non-empty, adds a CRITICAL watch that fires on ANY Admin Activity performed by one of them, so break-glass use is always noticed. Default [] = no break-glass watch. | `list(string)` | `[]` | no |
| <a name="input_cis_log_metric_name_prefix"></a> [cis\_log\_metric\_name\_prefix](#input\_cis\_log\_metric\_name\_prefix) | Prefix for the names of the CIS log-based metrics (the map key is appended). | `string` | `"cis-"` | no |
| <a name="input_cis_log_metrics"></a> [cis\_log\_metrics](#input\_cis\_log\_metrics) | CIS log-based metrics, keyed by a short name (used in the metric name). Each entry<br/>creates one google\_logging\_metric (DELTA / INT64 counter) and one alert policy on<br/>it. The default set is the CIS GCP Foundations v3.0 section 2.4-2.11 recommended<br/>filters, verbatim. Remove entries to stop monitoring them or add your own. | <pre>map(object({<br/>    display_name  = string<br/>    cis_control   = optional(string)<br/>    filter        = string<br/>    severity      = optional(string, "WARNING")<br/>    documentation = optional(string)<br/>  }))</pre> | <pre>{<br/>  "audit_config_change": {<br/>    "cis_control": "2.5",<br/>    "display_name": "Audit configuration change",<br/>    "filter": "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*",<br/>    "severity": "ERROR"<br/>  },<br/>  "custom_role_change": {<br/>    "cis_control": "2.6",<br/>    "display_name": "Custom role change",<br/>    "filter": "resource.type=\"iam_role\" AND (protoPayload.methodName=\"google.iam.admin.v1.CreateRole\" OR protoPayload.methodName=\"google.iam.admin.v1.DeleteRole\" OR protoPayload.methodName=\"google.iam.admin.v1.UpdateRole\")"<br/>  },<br/>  "project_ownership_change": {<br/>    "cis_control": "2.4",<br/>    "display_name": "Project ownership assignment or change",<br/>    "filter": "(protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\") AND (ProjectOwnership OR projectOwnerInvitee) OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"REMOVE\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"ADD\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\")",<br/>    "severity": "ERROR"<br/>  },<br/>  "sql_instance_config_change": {<br/>    "cis_control": "2.11",<br/>    "display_name": "Cloud SQL instance configuration change",<br/>    "filter": "protoPayload.methodName=\"cloudsql.instances.update\""<br/>  },<br/>  "storage_iam_change": {<br/>    "cis_control": "2.10",<br/>    "display_name": "Cloud Storage IAM permission change",<br/>    "filter": "resource.type=\"gcs_bucket\" AND protoPayload.methodName=\"storage.setIamPermissions\""<br/>  },<br/>  "vpc_firewall_rule_change": {<br/>    "cis_control": "2.7",<br/>    "display_name": "VPC firewall rule change",<br/>    "filter": "resource.type=\"gce_firewall_rule\" AND (protoPayload.methodName:\"compute.firewalls.patch\" OR protoPayload.methodName:\"compute.firewalls.insert\" OR protoPayload.methodName:\"compute.firewalls.delete\")"<br/>  },<br/>  "vpc_network_change": {<br/>    "cis_control": "2.9",<br/>    "display_name": "VPC network change",<br/>    "filter": "resource.type=\"gce_network\" AND (protoPayload.methodName:\"compute.networks.insert\" OR protoPayload.methodName:\"compute.networks.patch\" OR protoPayload.methodName:\"compute.networks.delete\" OR protoPayload.methodName:\"compute.networks.removePeering\" OR protoPayload.methodName:\"compute.networks.addPeering\")"<br/>  },<br/>  "vpc_route_change": {<br/>    "cis_control": "2.8",<br/>    "display_name": "VPC network route change",<br/>    "filter": "resource.type=\"gce_route\" AND (protoPayload.methodName:\"compute.routes.delete\" OR protoPayload.methodName:\"compute.routes.insert\")"<br/>  }<br/>}</pre> | no |
| <a name="input_enable"></a> [enable](#input\_enable) | Master gate. When false the module creates nothing (no channels, no alert policies). | `bool` | `true` | no |
| <a name="input_enable_cis_log_metrics"></a> [enable\_cis\_log\_metrics](#input\_enable\_cis\_log\_metrics) | Create the CIS GCP Foundations 2.4-2.11 log-based metrics in project\_id, each with<br/>a threshold alert policy that fires on any matching entry. With org\_id set, the<br/>aggregated org sink (include\_children = true) routes every project's Admin Activity<br/>logs into project\_id, so one set of metrics and alerts covers the whole org. | `bool` | `true` | no |
| <a name="input_enable_log_export_error_alert"></a> [enable\_log\_export\_error\_alert](#input\_enable\_log\_export\_error\_alert) | Also alert when the audit-log export sink reports delivery errors (a stalled audit pipeline). Requires the logging\_sink metric to exist in project\_id. | `bool` | `true` | no |
| <a name="input_extra_notification_channel_ids"></a> [extra\_notification\_channel\_ids](#input\_extra\_notification\_channel\_ids) | IDs of pre-existing notification channels to attach to every alert, in addition to the channels this module creates. | `list(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | User labels applied to the notification channels. | `map(string)` | `{}` | no |
| <a name="input_notification_email_addresses"></a> [notification\_email\_addresses](#input\_notification\_email\_addresses) | Email addresses to notify. Each becomes an email notification channel attached to every alert. | `list(string)` | `[]` | no |
| <a name="input_notification_rate_limit_seconds"></a> [notification\_rate\_limit\_seconds](#input\_notification\_rate\_limit\_seconds) | Minimum seconds between notifications for a single watch, so a burst of matching entries does not flood the channel. | `number` | `300` | no |
| <a name="input_notification_webhook_urls"></a> [notification\_webhook\_urls](#input\_notification\_webhook\_urls) | Map of label to webhook URL (e.g. Slack) to notify, in addition to email. Marked sensitive because URLs can embed tokens. | `map(string)` | `{}` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Numeric organization ID. When set, the module creates an aggregated org log sink<br/>that routes the org's Admin Activity and Policy audit logs (including org- and<br/>folder-level entries, which are never stored in any project) into project\_id, so the<br/>log-match watches can see them. Leave null only if logs are already routed into<br/>project\_id by other means. | `string` | `null` | no |
| <a name="input_org_log_route_sink_name"></a> [org\_log\_route\_sink\_name](#input\_org\_log\_route\_sink\_name) | Name of the aggregated org sink created when org\_id is set. | `string` | `"org-control-plane-to-monitoring"` | no |
| <a name="input_watches"></a> [watches](#input\_watches) | Guardrail-mutation watches, keyed by a short name. Each creates one log-match<br/>alert policy: a matching Admin Activity audit-log entry fires the alert. The<br/>default set covers the landing zone's control plane (org policy, org/folder<br/>IAM, VPC Service Controls, audit config, and logging sinks). Admins have full<br/>control: remove entries to stop watching them, change a filter, or add custom<br/>watches. Each entry sets display\_name, filter, optional severity (defaults to<br/>WARNING), and optional documentation. | <pre>map(object({<br/>    display_name  = string<br/>    filter        = string<br/>    severity      = optional(string, "WARNING")<br/>    documentation = optional(string)<br/>  }))</pre> | <pre>{<br/>  "audit_config_change": {<br/>    "display_name": "Audit logging configuration changed",<br/>    "filter": "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*",<br/>    "severity": "ERROR"<br/>  },<br/>  "custom_role_change": {<br/>    "display_name": "Custom IAM role created, updated or deleted",<br/>    "filter": "protoPayload.serviceName=\"iam.googleapis.com\" AND protoPayload.methodName:(\"CreateRole\" OR \"UpdateRole\" OR \"DeleteRole\" OR \"UndeleteRole\")",<br/>    "severity": "WARNING"<br/>  },<br/>  "deny_policy_change": {<br/>    "display_name": "IAM deny policy changed",<br/>    "filter": "protoPayload.serviceName=\"iam.googleapis.com\" AND protoPayload.methodName:(\"Policies.CreatePolicy\" OR \"Policies.UpdatePolicy\" OR \"Policies.DeletePolicy\")",<br/>    "severity": "ERROR"<br/>  },<br/>  "kms_key_destroy": {<br/>    "display_name": "KMS key version destroy scheduled",<br/>    "filter": "protoPayload.serviceName=\"cloudkms.googleapis.com\" AND protoPayload.methodName=\"DestroyCryptoKeyVersion\"",<br/>    "severity": "ERROR"<br/>  },<br/>  "log_sink_change": {<br/>    "display_name": "Logging sink or exclusion created, updated or deleted",<br/>    "filter": "protoPayload.serviceName=\"logging.googleapis.com\" AND protoPayload.methodName:(\"CreateSink\" OR \"DeleteSink\" OR \"UpdateSink\" OR \"CreateExclusion\" OR \"UpdateExclusion\" OR \"DeleteExclusion\")",<br/>    "severity": "ERROR"<br/>  },<br/>  "org_iam_change": {<br/>    "display_name": "Organization or folder IAM policy changed",<br/>    "filter": "protoPayload.methodName=\"SetIamPolicy\" AND (resource.type=\"organization\" OR resource.type=\"folder\")",<br/>    "severity": "ERROR"<br/>  },<br/>  "org_policy_change": {<br/>    "display_name": "Organization policy changed",<br/>    "filter": "protoPayload.serviceName=\"orgpolicy.googleapis.com\" AND protoPayload.methodName:(\"SetOrgPolicy\" OR \"CreatePolicy\" OR \"UpdatePolicy\" OR \"DeletePolicy\")",<br/>    "severity": "ERROR"<br/>  },<br/>  "vpc_sc_change": {<br/>    "display_name": "VPC Service Controls perimeter changed",<br/>    "filter": "protoPayload.serviceName=\"accesscontextmanager.googleapis.com\" AND protoPayload.methodName:(\"Create\" OR \"Update\" OR \"Replace\" OR \"Delete\")",<br/>    "severity": "ERROR"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cis_alert_policy_ids"></a> [cis\_alert\_policy\_ids](#output\_cis\_alert\_policy\_ids) | Map of CIS log-metric key to the alert policy ID watching it (empty when disabled). |
| <a name="output_cis_log_metric_names"></a> [cis\_log\_metric\_names](#output\_cis\_log\_metric\_names) | Map of CIS log-metric key to the created log-based metric name (empty when disabled). |
| <a name="output_log_export_error_alert_policy_id"></a> [log\_export\_error\_alert\_policy\_id](#output\_log\_export\_error\_alert\_policy\_id) | ID of the audit-sink export-error alert policy, or null when disabled. |
| <a name="output_notification_channel_ids"></a> [notification\_channel\_ids](#output\_notification\_channel\_ids) | IDs of the notification channels this module created (email and webhook). |
| <a name="output_org_log_route_sink_name"></a> [org\_log\_route\_sink\_name](#output\_org\_log\_route\_sink\_name) | Name of the aggregated org sink routing audit logs into project\_id, or null when org\_id is unset. |
| <a name="output_watch_alert_policy_ids"></a> [watch\_alert\_policy\_ids](#output\_watch\_alert\_policy\_ids) | Map of watch name to the created alert policy ID. |
| <a name="output_watched_names"></a> [watched\_names](#output\_watched\_names) | Names of the guardrail watches that are active. |
<!-- END_TF_DOCS -->
