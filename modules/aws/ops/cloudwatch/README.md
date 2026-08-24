# AWS CloudWatch Monitoring Module

CloudWatch **metric alarms**, an optional **SNS topic** for notifications, and an
optional **dashboard** — the AWS parity counterpart to GCP's
`modules/gcp/monitoring/alert-policy` (alerts + notification channel) and
`modules/gcp/monitoring/compute-dashboard` (dashboard).

Alarms are defined as a map and each becomes an `aws_cloudwatch_metric_alarm`
namespaced by `name_prefix`. Notifications are opt-in: set `create_sns_topic =
true` to have the module make and wire a topic, or pass an existing
`sns_topic_arn`. The dashboard is gated by `enable_dashboard` and its body is
built with `jsonencode()` from `dashboard_widgets`.

## Usage

```hcl
module "monitoring" {
  source = "../../ops/cloudwatch"

  name_prefix      = "prod"
  create_sns_topic = true

  alarms = {
    high-cpu = {
      namespace           = "AWS/EC2"
      metric_name         = "CPUUtilization"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      period              = 300
      evaluation_periods  = 3
    }
    alb-5xx = {
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_ELB_5XX_Count"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 10
    }
  }

  enable_dashboard = true
}
```

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name_prefix = 
	
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


- resource.aws_cloudwatch_dashboard.this (modules/aws/ops/cloudwatch/main.tf#L54)
- resource.aws_cloudwatch_metric_alarm.this (modules/aws/ops/cloudwatch/main.tf#L33)
- resource.aws_sns_topic.this (modules/aws/ops/cloudwatch/main.tf#L26)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to created resource names (SNS topic, dashboard) and used to namespace alarms. | `string` | n/a | yes |
| <a name="input_alarms"></a> [alarms](#input\_alarms) | Map of CloudWatch metric alarms to create, keyed by alarm name. The parity counterpart to GCP's monitoring/alert-policy. | <pre>map(object({<br/>    namespace           = string<br/>    metric_name         = string<br/>    statistic           = optional(string, "Average")<br/>    comparison_operator = string<br/>    threshold           = number<br/>    period              = optional(number, 300)<br/>    evaluation_periods  = optional(number, 1)<br/>    datapoints_to_alarm = optional(number)<br/>    dimensions          = optional(map(string), {})<br/>    treat_missing_data  = optional(string, "notBreaching")<br/>    alarm_description   = optional(string)<br/>    unit                = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_create_sns_topic"></a> [create\_sns\_topic](#input\_create\_sns\_topic) | Create an SNS topic and wire it as the alarm/OK action for every alarm. When false, supply sns\_topic\_arn to reuse an existing topic (or leave null for no notifications). | `bool` | `false` | no |
| <a name="input_dashboard_name"></a> [dashboard\_name](#input\_dashboard\_name) | Name of the CloudWatch dashboard (defaults to "<name\_prefix>-dashboard" when null). | `string` | `null` | no |
| <a name="input_dashboard_widgets"></a> [dashboard\_widgets](#input\_dashboard\_widgets) | List of CloudWatch dashboard widget objects (rendered into the dashboard body via jsonencode). Empty = a minimal single-text-widget placeholder. | `list(any)` | `[]` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Create a CloudWatch dashboard from dashboard\_widgets. The parity counterpart to GCP's monitoring/compute-dashboard. | `bool` | `false` | no |
| <a name="input_sns_kms_master_key_id"></a> [sns\_kms\_master\_key\_id](#input\_sns\_kms\_master\_key\_id) | KMS key id/alias for encrypting the created SNS topic (only used when create\_sns\_topic = true). Null = AWS-managed key. | `string` | `null` | no |
| <a name="input_sns_topic_arn"></a> [sns\_topic\_arn](#input\_sns\_topic\_arn) | Existing SNS topic ARN to use for alarm/OK actions when create\_sns\_topic = false. Null = no notification actions. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to taggable resources (SNS topic). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_arns"></a> [alarm\_arns](#output\_alarm\_arns) | Map of alarm key to the created CloudWatch metric alarm ARN. |
| <a name="output_dashboard_arn"></a> [dashboard\_arn](#output\_dashboard\_arn) | ARN of the CloudWatch dashboard, or null when enable\_dashboard = false. |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS topic used for alarm actions (created or passed-in); null if none. |
<!-- END_TF_DOCS -->
