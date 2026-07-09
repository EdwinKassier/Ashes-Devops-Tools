# service-quotas

Service-quota management for the SRA landing zone. **Opt-in — disabled by
default.** For each requested quota increase it files a service-quota request
and provisions an `AWS/Usage` CloudWatch alarm that fires at **~80%** of the
requested value, routing to the security-notifications SNS topic.

This implements AWS Well-Architected **REL01-BP04/05** (monitor and manage
service quotas), giving early warning before a quota is exhausted.

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


- resource.aws_cloudwatch_metric_alarm.usage (modules/aws/service-quotas/main.tf#L19)
- resource.aws_servicequotas_service_quota.this (modules/aws/service-quotas/main.tf#L10)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_service_quotas"></a> [enable\_service\_quotas](#input\_enable\_service\_quotas) | Master switch for service-quota management. Opt-in: when false (the default), no quota requests or usage alarms are created. | `bool` | `false` | no |
| <a name="input_notifications_topic_arn"></a> [notifications\_topic\_arn](#input\_notifications\_topic\_arn) | ARN of the SNS topic (from the security-notifications module) that usage alarms route to. When empty, alarms are created with no actions. | `string` | `""` | no |
| <a name="input_quota_increases"></a> [quota\_increases](#input\_quota\_increases) | Map of quota-increase requests keyed by an arbitrary name. Each entry files a service-quota request and provisions an AWS/Usage alarm at ~80% of the requested value. | <pre>map(object({<br/>    service_code = string # e.g. "ec2"<br/>    quota_code   = string # e.g. "L-1216C47A"<br/>    value        = number # requested quota value<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_names"></a> [alarm\_names](#output\_alarm\_names) | Names of the AWS/Usage CloudWatch alarms created for each quota-increase request. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "service_quotas" {
  source = "../../modules/aws/service-quotas"

  enable_service_quotas = true

  quota_increases = {
    ec2-standard-vcpus = {
      service_code = "ec2"
      quota_code   = "L-1216C47A"
      value        = 256
    }
  }

  # Route usage alarms to the security-notifications topic.
  notifications_topic_arn = module.security_notifications.topic_arn
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
