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
