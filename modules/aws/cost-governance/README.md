# cost-governance

Management-account-scoped cost governance for the SRA landing zone: monthly
budgets with threshold notifications, Cost Anomaly Detection, and cost-allocation
tag activation.

Because consolidated billing rolls every member account's spend up to the payer,
budgets and anomaly detection are organization-wide only from the management
(payer) account. This module is therefore composed by the `aws-organization`
stage, whose default provider is the management account.

What it creates (all gated behind `enable_cost_governance`):

- **Budgets** — one monthly `COST` budget per `budgets` entry, each with a
  percentage-threshold `ACTUAL`-spend notification that fans out to an optional
  SNS topic and any per-budget email subscribers.
- **Cost Anomaly Detection** — a `DIMENSIONAL`/`SERVICE` anomaly monitor plus a
  `DAILY` email subscription. The service monitor watches the always-on services
  (Convention 10), so a spend spike on any service surfaces as an anomaly. The
  subscription only alerts above an absolute-dollar-impact threshold
  (`ANOMALY_TOTAL_IMPACT_ABSOLUTE`).
- **Cost-allocation tags** — activates the B3 tag-policy keys (`CostCenter`,
  `Environment`, `Owner` by default) in Cost Explorer / the Cost & Usage Report
  so spend can be sliced by those dimensions. `status` is title-case `Active`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_budgets_budget.this (modules/aws/cost-governance/main.tf#L24)
- resource.aws_ce_anomaly_monitor.this (modules/aws/cost-governance/main.tf#L46)
- resource.aws_ce_anomaly_subscription.this (modules/aws/cost-governance/main.tf#L54)
- resource.aws_ce_cost_allocation_tag.this (modules/aws/cost-governance/main.tf#L80)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_anomaly_email"></a> [anomaly\_email](#input\_anomaly\_email) | Email address that receives Cost Anomaly Detection alerts. | `string` | `"finops@example.com"` | no |
| <a name="input_anomaly_monitor_name"></a> [anomaly\_monitor\_name](#input\_anomaly\_monitor\_name) | Name of the DIMENSIONAL/SERVICE Cost Anomaly Detection monitor. | `string` | `"org-service-monitor"` | no |
| <a name="input_anomaly_subscription_name"></a> [anomaly\_subscription\_name](#input\_anomaly\_subscription\_name) | Name of the Cost Anomaly Detection subscription wired to the monitor. | `string` | `"org-anomaly-sub"` | no |
| <a name="input_anomaly_threshold_usd"></a> [anomaly\_threshold\_usd](#input\_anomaly\_threshold\_usd) | Absolute dollar impact (USD) at or above which an anomaly triggers an alert (ANOMALY\_TOTAL\_IMPACT\_ABSOLUTE). | `number` | `100` | no |
| <a name="input_budgets"></a> [budgets](#input\_budgets) | Monthly COST budgets keyed by budget name. limit\_amount is the USD limit; threshold\_percent triggers an ACTUAL-spend notification when crossed; emails receive the notification alongside the optional SNS topic. | <pre>map(object({<br/>    limit_amount      = string<br/>    threshold_percent = number<br/>    emails            = optional(list(string), [])<br/>  }))</pre> | <pre>{<br/>  "org-monthly": {<br/>    "limit_amount": "1000",<br/>    "threshold_percent": 80<br/>  }<br/>}</pre> | no |
| <a name="input_cost_allocation_tags"></a> [cost\_allocation\_tags](#input\_cost\_allocation\_tags) | Tag keys to activate as cost-allocation tags in Cost Explorer / the Cost & Usage Report. Should mirror the B3 tag-policy keys. | `list(string)` | <pre>[<br/>  "CostCenter",<br/>  "Environment",<br/>  "Owner"<br/>]</pre> | no |
| <a name="input_enable_cost_governance"></a> [enable\_cost\_governance](#input\_enable\_cost\_governance) | Master gate. When false, no budgets, anomaly monitor/subscription or cost-allocation tags are created (the module composes as a no-op). | `bool` | `true` | no |
| <a name="input_notifications_topic_arn"></a> [notifications\_topic\_arn](#input\_notifications\_topic\_arn) | Optional SNS topic ARN that budget notifications are published to, in addition to any per-budget email subscribers. Empty string disables SNS fan-out. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_anomaly_monitor_arn"></a> [anomaly\_monitor\_arn](#output\_anomaly\_monitor\_arn) | ARN of the Cost Anomaly Detection monitor, or null when cost governance is disabled. |
| <a name="output_budget_ids"></a> [budget\_ids](#output\_budget\_ids) | Map of budget name to the created budget resource ID. Empty when cost governance is disabled. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "cost_governance" {
  source = "../../modules/aws/cost-governance"

  # Defaults provide a single org-monthly budget, a DIMENSIONAL/SERVICE anomaly
  # monitor + daily subscription, and the three default cost-allocation tags.
  budgets = {
    org-monthly = { limit_amount = "5000", threshold_percent = 80, emails = ["finops@example.com"] }
  }

  notifications_topic_arn = "arn:aws:sns:eu-west-2:111111111111:cost-alerts"
  anomaly_email           = "finops@example.com"
  anomaly_threshold_usd   = 250
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
