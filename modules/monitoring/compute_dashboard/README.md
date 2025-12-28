# Unified Compute Dashboard Module

Terraform module that creates a comprehensive Cloud Monitoring dashboard for viewing Cloud Run and Cloud Functions performance metrics across a GCP project.

## Features

- **Unified view** of Cloud Run and Cloud Functions (Gen1 & Gen2) metrics
- **Health scorecards** for quick status overview
- **Error tracking** with 5xx/4xx breakdown
- **Latency monitoring** with p50/p95/p99 percentiles
- **Resource utilization** heatmaps (CPU/Memory)
- **Cost visibility** via billable instance time metrics

## Usage

```hcl
module "compute_dashboard" {
  source = "./modules/monitoring/compute_dashboard"

  project_id             = "my-project-id"
  dashboard_display_name = "Unified Compute Dashboard"
  
  # Optional: thresholds for scorecard indicators
  latency_threshold_ms         = 1000
  error_rate_threshold_percent = 1.0
  
  # Optional: include Gen1 Cloud Functions metrics
  include_gen1_functions = true
}
```

## Outputs

| Output | Description |
|--------|-------------|
| `dashboard_id` | The ID of the created dashboard |
| `dashboard_console_url` | Direct link to the dashboard in GCP Console |

## Requirements

- Google Provider >= 5.0 (6.0+ recommended)
- Required APIs:
  - `monitoring.googleapis.com`
  - `run.googleapis.com`
  - `cloudfunctions.googleapis.com`
- IAM Role: `roles/monitoring.dashboardEditor`

## Note on Gen2 Functions

Gen2 Cloud Functions (now "Cloud Run functions") emit metrics under `run.googleapis.com/*`. Set `include_gen1_functions = false` if you only use Gen2.
