# gcp/monitoring/slo

A service-level objective for a monitored service, with an optional error-budget
burn-rate alert. Part of the application observability layer (audit C1): attach it
to the monitored service of a Cloud Run or GKE workload to track availability or
latency against a goal and get paged before the SLO is missed. The
`gcp/stages/app-services` golden path composes it for every service that sets
`slo`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	display_name =
	project_id =
	service_id =
	slo_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |



## Resources

The following resources are created:


- resource.google_monitoring_alert_policy.burn_rate (modules/gcp/monitoring/slo/main.tf#L35)
- resource.google_monitoring_slo.this (modules/gcp/monitoring/slo/main.tf#L6)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | Human-readable SLO name, e.g. 'API 99.9% availability'. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project that owns the SLO and the monitored service. | `string` | n/a | yes |
| <a name="input_service_id"></a> [service\_id](#input\_service\_id) | ID of the monitored service the SLO is attached to (e.g. the google\_monitoring\_service for a Cloud Run service). | `string` | n/a | yes |
| <a name="input_slo_id"></a> [slo\_id](#input\_slo\_id) | Stable ID for this SLO within the service. | `string` | n/a | yes |
| <a name="input_burn_rate_lookback"></a> [burn\_rate\_lookback](#input\_burn\_rate\_lookback) | Lookback window for the burn-rate calculation, e.g. '3600s'. | `string` | `"3600s"` | no |
| <a name="input_burn_rate_threshold"></a> [burn\_rate\_threshold](#input\_burn\_rate\_threshold) | Burn-rate multiple that triggers the alert (e.g. 10 = burning 10x the sustainable rate). | `number` | `10` | no |
| <a name="input_enable_burn_rate_alert"></a> [enable\_burn\_rate\_alert](#input\_enable\_burn\_rate\_alert) | Create an alert policy on fast error-budget burn. Default false; set notification\_channels when enabling. | `bool` | `false` | no |
| <a name="input_goal"></a> [goal](#input\_goal) | SLO target as a fraction, e.g. 0.999 for 99.9%. | `number` | `0.99` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource this module creates (merged with the provider default\_labels; resource-specific labels win). | `map(string)` | `{}` | no |
| <a name="input_latency_threshold"></a> [latency\_threshold](#input\_latency\_threshold) | Latency threshold (e.g. '1s') for a latency SLI. Required when sli\_type = latency. | `string` | `"1s"` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | Monitoring notification channel IDs for the burn-rate alert. | `list(string)` | `[]` | no |
| <a name="input_rolling_period_days"></a> [rolling\_period\_days](#input\_rolling\_period\_days) | Rolling compliance window in days (e.g. 28). | `number` | `28` | no |
| <a name="input_sli_type"></a> [sli\_type](#input\_sli\_type) | Which basic SLI to measure: 'availability' or 'latency'. | `string` | `"availability"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_burn_rate_alert_policy_id"></a> [burn\_rate\_alert\_policy\_id](#output\_burn\_rate\_alert\_policy\_id) | ID of the burn-rate alert policy, or null when not enabled. |
| <a name="output_slo_name"></a> [slo\_name](#output\_slo\_name) | Full resource name of the SLO. |
<!-- END_TF_DOCS -->
