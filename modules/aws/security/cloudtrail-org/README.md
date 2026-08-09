# cloudtrail-org

Organization-wide, multi-Region AWS CloudTrail for the SRA landing zone. Creates
a single organization trail that captures management and global-service events
across every account and delivers them to the central Log-Archive bucket, with
log-file validation enabled for audit-grade integrity.

> **Account placement.** This module must be applied with the **management-account**
> (or CloudTrail delegated-admin) provider — organization trails can only be
> owned by the management or delegated-administrator account. `log_archive_bucket`
> names the central **Log-Archive** bucket, which lives in a *different* account;
> delivery to it is authorized by that bucket's resource policy. The composing
> stage wires a `depends_on` from this trail to the bucket policy so the policy
> exists before CloudTrail validates delivery — that ordering is a stage concern
> and is not expressed here at the module level.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	kms_key_arn = 
	log_archive_bucket = 
	
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


- resource.aws_cloudtrail.org (modules/aws/security/cloudtrail-org/main.tf#L19)
- resource.aws_cloudwatch_log_group.trail (modules/aws/security/cloudtrail-org/main.tf#L41)
- resource.aws_cloudwatch_log_metric_filter.cis (modules/aws/security/cloudtrail-org/main.tf#L88)
- resource.aws_cloudwatch_metric_alarm.cis (modules/aws/security/cloudtrail-org/main.tf#L100)
- resource.aws_iam_role.cloudtrail_cw (modules/aws/security/cloudtrail-org/main.tf#L52)
- resource.aws_iam_role_policy.cloudtrail_cw (modules/aws/security/cloudtrail-org/main.tf#L65)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt the CloudTrail log files delivered to the Log-Archive bucket. | `string` | n/a | yes |
| <a name="input_log_archive_bucket"></a> [log\_archive\_bucket](#input\_log\_archive\_bucket) | Name of the central Log-Archive S3 bucket that receives the trail's log files. This bucket lives in the Log-Archive account (a different account from the trail owner); its resource policy authorizes CloudTrail delivery. | `string` | n/a | yes |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | Optional SNS topic ARN for CIS alarm notifications (enable\_cloudwatch\_logs). Null = alarms created without notification action. | `string` | `null` | no |
| <a name="input_cloudwatch_logs_kms_key_arn"></a> [cloudwatch\_logs\_kms\_key\_arn](#input\_cloudwatch\_logs\_kms\_key\_arn) | Optional CMK ARN for the CloudWatch Logs group when enable\_cloudwatch\_logs = true. Its key policy MUST grant logs.<region>.amazonaws.com (audit C1). Null = AWS-managed encryption (no grant required). | `string` | `null` | no |
| <a name="input_cloudwatch_logs_retention_days"></a> [cloudwatch\_logs\_retention\_days](#input\_cloudwatch\_logs\_retention\_days) | Retention (days) for the CloudWatch Logs group when enable\_cloudwatch\_logs = true. | `number` | `365` | no |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | When true, attach a CloudWatch Logs group to the org trail and create CIS control-plane metric-filter alarms (audit A4). Default false preserves the deliberate S3-only design. UNVALIDATED — validate on a real org. | `bool` | `false` | no |
| <a name="input_trail_name"></a> [trail\_name](#input\_trail\_name) | Name of the organization CloudTrail trail. | `string` | `"org-trail"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_trail_arn"></a> [trail\_arn](#output\_trail\_arn) | The ARN of the organization CloudTrail trail. |
| <a name="output_trail_name"></a> [trail\_name](#output\_trail\_name) | The name of the organization CloudTrail trail. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "cloudtrail_org" {
  source = "../../modules/aws/cloudtrail-org"

  # Apply with the management-account / delegated-admin provider.
  log_archive_bucket = "sra-log-archive-bucket"
  kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
