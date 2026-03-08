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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_monitoring_dashboard.compute_dashboard (modules/monitoring/compute_dashboard/main.tf#L435)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID where the dashboard will be created | `string` | n/a | yes |
| <a name="input_dashboard_display_name"></a> [dashboard\_display\_name](#input\_dashboard\_display\_name) | Display name for the monitoring dashboard | `string` | `"Unified Compute Dashboard"` | no |
| <a name="input_error_rate_threshold_percent"></a> [error\_rate\_threshold\_percent](#input\_error\_rate\_threshold\_percent) | Error rate threshold percentage for scorecard warning indicator | `number` | `1` | no |
| <a name="input_include_gen1_functions"></a> [include\_gen1\_functions](#input\_include\_gen1\_functions) | Include Gen1 Cloud Functions metrics (cloudfunctions.googleapis.com). Set to false if only using Gen2/Cloud Run functions. | `bool` | `true` | no |
| <a name="input_latency_threshold_ms"></a> [latency\_threshold\_ms](#input\_latency\_threshold\_ms) | P99 latency threshold in milliseconds for scorecard warning indicator | `number` | `1000` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dashboard_console_url"></a> [dashboard\_console\_url](#output\_dashboard\_console\_url) | Direct URL to access the dashboard in the GCP Console |
| <a name="output_dashboard_id"></a> [dashboard\_id](#output\_dashboard\_id) | The ID of the created monitoring dashboard |
<!-- END_TF_DOCS -->