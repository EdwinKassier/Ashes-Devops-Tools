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
