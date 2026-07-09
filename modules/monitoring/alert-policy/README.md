# monitoring/alert_policy

Creates Cloud Monitoring alert policies and notification channels for GCP workloads.

## Features

- **Email notifications** — one `google_monitoring_notification_channel` per address
- **Webhook notifications** — Slack, PagerDuty, or any HTTPS endpoint
- **CPU utilisation alert** — GCE instance CPU > threshold (requires Monitoring Agent)
- **Memory utilisation alert** — GCE instance memory > threshold (requires Ops Agent)
- **Cloud Run 5xx error rate alert** — `run.googleapis.com/request_count` filtered to `5xx` class
- **Cloud Run P99 latency alert** — `run.googleapis.com/request_latencies` at the 99th percentile
- **Uptime check failure alert** — attaches to existing uptime check IDs
- **Log-based alert** — fires on any log filter match (e.g. org-policy violations, IAM changes)
- **Prefix support** — all policies share a display-name prefix for easy console filtering

## Usage

```hcl
module "alerts" {
  source = "../../modules/monitoring/alert_policy"

  project_id = "my-workload-project"

  notification_email_addresses = ["ops@example.com"]
  notification_webhook_urls = {
    "slack-ops" = "https://hooks.slack.com/services/T.../B.../xxx"
  }

  # Tune to match your SLOs
  cpu_utilization_threshold    = 0.8
  memory_utilization_threshold = 0.85
  error_rate_threshold_percent = 0.01  # req/s
  latency_p99_threshold_ms     = 2000

  alert_display_name_prefix = "prod"
}
```

See [`examples/basic/`](examples/basic/) for a full example with log-based alerting.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_id` | GCP project ID | `string` | — | yes |
| `notification_email_addresses` | Email addresses to notify | `list(string)` | `[]` | no |
| `notification_webhook_urls` | Map of label → HTTPS webhook URL | `map(string)` | `{}` | no |
| `extra_notification_channel_ids` | Pre-existing channel IDs to attach | `list(string)` | `[]` | no |
| `enable_high_cpu_alert` | Create CPU alert | `bool` | `true` | no |
| `enable_high_memory_alert` | Create memory alert | `bool` | `true` | no |
| `enable_error_rate_alert` | Create 5xx error rate alert | `bool` | `true` | no |
| `enable_high_latency_alert` | Create P99 latency alert | `bool` | `true` | no |
| `enable_uptime_alert` | Create uptime failure alert | `bool` | `false` | no |
| `enable_log_based_alert` | Create log-based alert | `bool` | `false` | no |
| `cpu_utilization_threshold` | CPU fraction (0, 1] | `number` | `0.8` | no |
| `memory_utilization_threshold` | Memory fraction (0, 1] | `number` | `0.85` | no |
| `error_rate_threshold_percent` | 5xx rate (req/s) | `number` | `0.01` | no |
| `latency_p99_threshold_ms` | P99 latency (ms) | `number` | `2000` | no |
| `alert_alignment_period` | Aggregation window (s, min 60) | `number` | `60` | no |
| `alert_duration` | Sustained violation window (s) | `number` | `60` | no |
| `uptime_check_ids` | Uptime check IDs | `list(string)` | `[]` | no |
| `log_filter` | Log filter expression | `string` | `null` | no |
| `log_alert_display_name` | Display name for log-based alert | `string` | `"Log-Based Security Alert"` | no |
| `alert_display_name_prefix` | Prefix for all alert names | `string` | `""` | no |
| `labels` | Labels for notification channels | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `email_notification_channel_ids` | Map of email address → channel ID |
| `webhook_notification_channel_ids` | Map of webhook label → channel ID |
| `all_notification_channel_ids` | All channel IDs (created + extra) |
| `high_cpu_alert_policy_id` | CPU alert policy ID, or null |
| `high_memory_alert_policy_id` | Memory alert policy ID, or null |
| `error_rate_alert_policy_id` | Error rate alert policy ID, or null |
| `high_latency_alert_policy_id` | Latency alert policy ID, or null |
| `uptime_alert_policy_id` | Uptime alert policy ID, or null |
| `log_based_alert_policy_id` | Log-based alert policy ID, or null |
| `all_alert_policy_ids` | Map of alert name → policy ID for all enabled policies |

## Notes

### Sharing notification channels across modules

Pass `all_notification_channel_ids` from one module call into
`extra_notification_channel_ids` of another to reuse channels:

```hcl
module "alerts_primary" {
  source     = "../../modules/monitoring/alert_policy"
  project_id = "my-project"
  notification_email_addresses = ["ops@example.com"]
}

module "alerts_secondary" {
  source     = "../../modules/monitoring/alert_policy"
  project_id = "my-project"
  # No new channels — reuse the ones created above
  extra_notification_channel_ids = module.alerts_primary.all_notification_channel_ids
  enable_high_cpu_alert          = false
  enable_log_based_alert         = true
  log_filter                     = "severity=CRITICAL"
}
```

### Memory metric prerequisite

The memory alert uses `agent.googleapis.com/memory/percent_used`, which requires
the [Ops Agent](https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent)
to be installed on each GCE instance. Without the agent, the alert creates
successfully but will never fire.

### Cloud Run metrics

Error rate and latency alerts target `cloud_run_revision` resources. They will
generate no time-series (and therefore never fire) for GCE-only projects. Set
`enable_error_rate_alert = false` and `enable_high_latency_alert = false` in that
case to avoid noise.

### Required IAM

The identity running Terraform needs:
- `roles/monitoring.alertPolicyEditor` — to create/update alert policies
- `roles/monitoring.notificationChannelEditor` — to create notification channels

<!-- BEGIN_TF_DOCS -->
Copyright 2024 Ashes

Monitoring Alert Policy Module

Creates Cloud Monitoring alert policies and notification channels.
Supports email, Slack/webhook notifications, and common GCP metric alerts
(CPU, memory, error rate, latency, uptime, and log-based).

Usage:
  module "alerts" {
    source     = "../../modules/monitoring/alert-policy"
    project\_id = "my-project"
    notification\_email\_addresses = ["ops@example.com"]
    notification\_webhook\_urls = {
      "slack-ops" = "https://hooks.slack.com/services/..."
    }
  }

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_monitoring_alert_policy.error_rate (modules/monitoring/alert-policy/main.tf#L144)
- resource.google_monitoring_alert_policy.high_cpu (modules/monitoring/alert-policy/main.tf#L69)
- resource.google_monitoring_alert_policy.high_latency (modules/monitoring/alert-policy/main.tf#L186)
- resource.google_monitoring_alert_policy.high_memory (modules/monitoring/alert-policy/main.tf#L106)
- resource.google_monitoring_alert_policy.log_based (modules/monitoring/alert-policy/main.tf#L273)
- resource.google_monitoring_alert_policy.uptime (modules/monitoring/alert-policy/main.tf#L227)
- resource.google_monitoring_notification_channel.email (modules/monitoring/alert-policy/main.tf#L36)
- resource.google_monitoring_notification_channel.webhook (modules/monitoring/alert-policy/main.tf#L50)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID in which to create alert policies and notification channels. | `string` | n/a | yes |
| <a name="input_alert_alignment_period"></a> [alert\_alignment\_period](#input\_alert\_alignment\_period) | Alignment period (seconds) for time-series aggregation in alert conditions. Minimum 60. | `number` | `60` | no |
| <a name="input_alert_display_name_prefix"></a> [alert\_display\_name\_prefix](#input\_alert\_display\_name\_prefix) | Prefix applied to all alert policy display names for easy filtering in the console (e.g., 'prod', 'ashes-dev'). | `string` | `""` | no |
| <a name="input_alert_duration"></a> [alert\_duration](#input\_alert\_duration) | Duration (seconds) a condition must be sustained before the alert fires. Set to 0 to fire immediately on first violation. | `number` | `60` | no |
| <a name="input_cpu_utilization_threshold"></a> [cpu\_utilization\_threshold](#input\_cpu\_utilization\_threshold) | Fractional CPU utilisation (0.0–1.0) that triggers the CPU alert (e.g., 0.8 = 80%). | `number` | `0.8` | no |
| <a name="input_enable_error_rate_alert"></a> [enable\_error\_rate\_alert](#input\_enable\_error\_rate\_alert) | Create an alert policy that fires when the Cloud Run/GCF 5xx error rate exceeds var.error\_rate\_threshold\_percent. | `bool` | `true` | no |
| <a name="input_enable_high_cpu_alert"></a> [enable\_high\_cpu\_alert](#input\_enable\_high\_cpu\_alert) | Create an alert policy that fires when CPU utilisation exceeds var.cpu\_utilization\_threshold. | `bool` | `true` | no |
| <a name="input_enable_high_latency_alert"></a> [enable\_high\_latency\_alert](#input\_enable\_high\_latency\_alert) | Create an alert policy that fires when Cloud Run P99 request latency exceeds var.latency\_p99\_threshold\_ms. | `bool` | `true` | no |
| <a name="input_enable_high_memory_alert"></a> [enable\_high\_memory\_alert](#input\_enable\_high\_memory\_alert) | Create an alert policy that fires when memory utilisation exceeds var.memory\_utilization\_threshold. | `bool` | `true` | no |
| <a name="input_enable_log_based_alert"></a> [enable\_log\_based\_alert](#input\_enable\_log\_based\_alert) | Create a log-based alert that fires on matches to var.log\_filter. Useful for security events (e.g., org-policy violations). | `bool` | `false` | no |
| <a name="input_enable_uptime_alert"></a> [enable\_uptime\_alert](#input\_enable\_uptime\_alert) | Create an uptime check alert policy. Requires var.uptime\_check\_ids to be set. | `bool` | `false` | no |
| <a name="input_error_rate_threshold_percent"></a> [error\_rate\_threshold\_percent](#input\_error\_rate\_threshold\_percent) | 5xx error rate (requests/second) above which the error-rate alert fires. | `number` | `0.01` | no |
| <a name="input_extra_notification_channel_ids"></a> [extra\_notification\_channel\_ids](#input\_extra\_notification\_channel\_ids) | Additional pre-existing notification channel IDs to attach to all alert policies. Format: 'projects/<project>/notificationChannels/<id>'. | `list(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all notification channel resources. | `map(string)` | `{}` | no |
| <a name="input_latency_p99_threshold_ms"></a> [latency\_p99\_threshold\_ms](#input\_latency\_p99\_threshold\_ms) | P99 request latency in milliseconds above which the latency alert fires. | `number` | `2000` | no |
| <a name="input_log_alert_display_name"></a> [log\_alert\_display\_name](#input\_log\_alert\_display\_name) | Display name for the log-based alert policy. | `string` | `"Log-Based Security Alert"` | no |
| <a name="input_log_filter"></a> [log\_filter](#input\_log\_filter) | Log filter expression for the log-based alert. Required when enable\_log\_based\_alert = true. Example: 'severity=CRITICAL AND protoPayload.methodName="SetIamPolicy"'. | `string` | `null` | no |
| <a name="input_memory_utilization_threshold"></a> [memory\_utilization\_threshold](#input\_memory\_utilization\_threshold) | Fractional memory utilisation (0.0–1.0) that triggers the memory alert (e.g., 0.85 = 85%). | `number` | `0.85` | no |
| <a name="input_notification_email_addresses"></a> [notification\_email\_addresses](#input\_notification\_email\_addresses) | List of email addresses to notify when an alert fires. An<br/>google\_monitoring\_notification\_channel resource is created per address.<br/>Leave empty to skip email channel creation (use existing channel IDs via<br/>var.extra\_notification\_channel\_ids instead). | `list(string)` | `[]` | no |
| <a name="input_notification_webhook_urls"></a> [notification\_webhook\_urls](#input\_notification\_webhook\_urls) | Map of label → HTTPS webhook URL for alert notifications.<br/>Supports Slack incoming webhooks, PagerDuty, and any generic HTTP endpoint.<br/>Example: { "slack-ops" = "https://hooks.slack.com/services/T.../B.../xxx" }<br/>Marked sensitive: URLs contain embedded auth tokens and must not appear in<br/>plan output or be stored unredacted in CI logs. | `map(string)` | `{}` | no |
| <a name="input_uptime_check_ids"></a> [uptime\_check\_ids](#input\_uptime\_check\_ids) | List of existing uptime check IDs (format: 'projects/<project>/uptimeCheckConfigs/<id>') to create uptime failure alerts for. Required when enable\_uptime\_alert = true. | `list(string)` | `[]` | no |
| <a name="input_uptime_check_resource_type"></a> [uptime\_check\_resource\_type](#input\_uptime\_check\_resource\_type) | Monitored resource type used in the uptime check alert filter.<br/>Use "uptime\_url" for HTTP/HTTPS uptime checks (default).<br/>Use "uptime\_tcp" for TCP uptime checks.<br/>See: https://cloud.google.com/monitoring/api/resources | `string` | `"uptime_url"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_all_alert_policy_ids"></a> [all\_alert\_policy\_ids](#output\_all\_alert\_policy\_ids) | Map of alert name to policy resource ID for all enabled policies. |
| <a name="output_all_notification_channel_ids"></a> [all\_notification\_channel\_ids](#output\_all\_notification\_channel\_ids) | All notification channel IDs (created + extra). Pass this to other alert\_policy module calls to share channels. |
| <a name="output_email_notification_channel_ids"></a> [email\_notification\_channel\_ids](#output\_email\_notification\_channel\_ids) | Map of email address to notification channel resource ID. |
| <a name="output_error_rate_alert_policy_id"></a> [error\_rate\_alert\_policy\_id](#output\_error\_rate\_alert\_policy\_id) | Resource ID of the error rate alert policy, or null when disabled. |
| <a name="output_high_cpu_alert_policy_id"></a> [high\_cpu\_alert\_policy\_id](#output\_high\_cpu\_alert\_policy\_id) | Resource ID of the high CPU alert policy, or null when disabled. |
| <a name="output_high_latency_alert_policy_id"></a> [high\_latency\_alert\_policy\_id](#output\_high\_latency\_alert\_policy\_id) | Resource ID of the high latency alert policy, or null when disabled. |
| <a name="output_high_memory_alert_policy_id"></a> [high\_memory\_alert\_policy\_id](#output\_high\_memory\_alert\_policy\_id) | Resource ID of the high memory alert policy, or null when disabled. |
| <a name="output_log_based_alert_policy_id"></a> [log\_based\_alert\_policy\_id](#output\_log\_based\_alert\_policy\_id) | Resource ID of the log-based alert policy, or null when disabled. |
| <a name="output_uptime_alert_policy_id"></a> [uptime\_alert\_policy\_id](#output\_uptime\_alert\_policy\_id) | Resource ID of the uptime alert policy, or null when disabled. |
| <a name="output_webhook_notification_channel_ids"></a> [webhook\_notification\_channel\_ids](#output\_webhook\_notification\_channel\_ids) | Map of webhook label to notification channel resource ID. Marked sensitive: channel IDs are tied to webhook URLs that embed auth tokens. |
<!-- END_TF_DOCS -->