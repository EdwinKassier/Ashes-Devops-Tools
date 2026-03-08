# Cloud Billing Budget Module

Creates billing budgets and alerts for Google Cloud projects.

## Features

- Flexible budget filtering (projects, services, labels)
- Multiple threshold rules (50%, 90%, 100%)
- Forecasted spend alerting
- Pub/Sub notifications for programmatic reactions
- Email notifications via Cloud Functions (optional)

## Usage

### Simple Budget
```hcl
module "budget" {
  source = "../../governance/billing"

  project_id           = "my-billing-project"
  billing_account      = "000000-000000-000000"
  project_name         = "my-project"
  monthly_budget_limit = 1000
  projects             = ["projects/my-project"]
}
```

### With Email Notifications
```hcl
module "budget" {
  source = "../../governance/billing"

  # ... basic args ...

  enable_email_notifications = true
  email_recipients          = ["admin@example.com", "finops@example.com"]
  sendgrid_api_key_secret_id = "projects/123/secrets/sendgrid-key/versions/1"
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| billing_account | Billing account ID | string | yes |
| monthly_budget_limit | Budget limit in currency | number | yes |
| projects | List of projects to monitor | list(string) | yes |
| alert_threshold_percent | First alert threshold | number | no (default 0.5) |

## Outputs

| Name | Description |
|------|-------------|
| budget_name | The name of the created budget |
| alerting_topic | Pub/Sub topic for alerts |

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	billing_account = 
	monthly_budget_limit = 
	project_id = 
	project_name = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_billing_budget.monthly_budget (modules/governance/billing/main.tf#L5)
- resource.google_cloudfunctions_function.budget_notifier (modules/governance/billing/main.tf#L108)
- resource.google_cloudfunctions_function_iam_member.invoker (modules/governance/billing/main.tf#L143)
- resource.google_pubsub_subscription.budget_alerts_sub (modules/governance/billing/main.tf#L74)
- resource.google_pubsub_topic.budget_alerts (modules/governance/billing/main.tf#L59)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | The ID of the billing account to create budget for | `string` | n/a | yes |
| <a name="input_monthly_budget_limit"></a> [monthly\_budget\_limit](#input\_monthly\_budget\_limit) | The monthly budget limit in the specified currency | `number` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where resources will be created | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | The name prefix for resources | `string` | n/a | yes |
| <a name="input_alert_threshold_percent"></a> [alert\_threshold\_percent](#input\_alert\_threshold\_percent) | The percentage threshold for the first alert (0.5 = 50%) | `number` | `0.5` | no |
| <a name="input_currency_code"></a> [currency\_code](#input\_currency\_code) | The currency code for the budget (e.g., USD, EUR, GBP) | `string` | `"USD"` | no |
| <a name="input_email_recipients"></a> [email\_recipients](#input\_email\_recipients) | List of email addresses to receive budget alerts | `list(string)` | `[]` | no |
| <a name="input_enable_email_notifications"></a> [enable\_email\_notifications](#input\_enable\_email\_notifications) | Enable email notifications via Cloud Function | `bool` | `false` | no |
| <a name="input_function_source_object"></a> [function\_source\_object](#input\_function\_source\_object) | Cloud Storage object name for the Cloud Function source | `string` | `""` | no |
| <a name="input_functions_bucket"></a> [functions\_bucket](#input\_functions\_bucket) | Cloud Storage bucket containing the Cloud Function source code | `string` | `""` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Optional customer-managed KMS key used to encrypt the budget alert Pub/Sub topic | `string` | `null` | no |
| <a name="input_label_filters"></a> [label\_filters](#input\_label\_filters) | Map of label keys to values for filtering budget scope (single value per key) | `map(string)` | `{}` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of monitoring notification channel IDs | `list(string)` | `[]` | no |
| <a name="input_projects"></a> [projects](#input\_projects) | List of project IDs to monitor in the budget | `list(string)` | `[]` | no |
| <a name="input_pubsub_service_account"></a> [pubsub\_service\_account](#input\_pubsub\_service\_account) | Service account used by Pub/Sub to invoke Cloud Function | `string` | `"service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where Cloud Function will be deployed | `string` | `"us-central1"` | no |
| <a name="input_sendgrid_api_key_secret_id"></a> [sendgrid\_api\_key\_secret\_id](#input\_sendgrid\_api\_key\_secret\_id) | Secret Manager secret ID for SendGrid API key (recommended to use Secret Manager) | `string` | `""` | no |
| <a name="input_service_filters"></a> [service\_filters](#input\_service\_filters) | List of GCP service IDs to include in budget (empty = all services) | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_webhook_endpoint"></a> [webhook\_endpoint](#input\_webhook\_endpoint) | Optional webhook endpoint to receive budget alerts | `string` | `""` | no |
| <a name="input_webhook_service_account"></a> [webhook\_service\_account](#input\_webhook\_service\_account) | Service account for authenticating webhook requests | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alert_thresholds"></a> [alert\_thresholds](#output\_alert\_thresholds) | The configured alert thresholds |
| <a name="output_budget_amount"></a> [budget\_amount](#output\_budget\_amount) | The configured budget amount |
| <a name="output_budget_id"></a> [budget\_id](#output\_budget\_id) | The ID of the budget |
| <a name="output_budget_name"></a> [budget\_name](#output\_budget\_name) | The display name of the budget |
| <a name="output_budget_notifier_function_name"></a> [budget\_notifier\_function\_name](#output\_budget\_notifier\_function\_name) | The name of the Cloud Function for budget notifications |
| <a name="output_budget_notifier_function_url"></a> [budget\_notifier\_function\_url](#output\_budget\_notifier\_function\_url) | The URL of the Cloud Function for budget notifications |
| <a name="output_pubsub_subscription_id"></a> [pubsub\_subscription\_id](#output\_pubsub\_subscription\_id) | The ID of the Pub/Sub subscription for budget alerts |
| <a name="output_pubsub_subscription_name"></a> [pubsub\_subscription\_name](#output\_pubsub\_subscription\_name) | The name of the Pub/Sub subscription for budget alerts |
| <a name="output_pubsub_topic_id"></a> [pubsub\_topic\_id](#output\_pubsub\_topic\_id) | The ID of the Pub/Sub topic for budget alerts |
| <a name="output_pubsub_topic_name"></a> [pubsub\_topic\_name](#output\_pubsub\_topic\_name) | The name of the Pub/Sub topic for budget alerts |
<!-- END_TF_DOCS -->