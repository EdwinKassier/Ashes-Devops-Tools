# cloudtrail-org

Organization-wide, multi-Region AWS CloudTrail for the SRA landing zone. Creates
a single organization trail that captures management and global-service events
across every account and delivers them to the central Log-Archive bucket, with
log-file validation enabled for audit-grade integrity.

**Data events (CIS AWS 3.8 / 3.9).** Advanced event selectors record S3
object-level events. The default is `cloudtrail_s3_data_events = "write"`
(CIS 3.8); use `read` (3.9) or `all` (both), or `none`. The log-archive bucket is
excluded by default (`exclude_log_archive_bucket_from_data_events`), because
otherwise CloudTrail would record its own deliveries. Lambda invoke events are
optional (`enable_lambda_data_events`). **Cost:** data events are billed per
event ($0.10 per 100,000 at list price) across every account in the org. `read`
and `all` on busy buckets can cost more than the rest of the trail; exclude
high-volume buckets with `s3_data_events_excluded_bucket_arns`.

**CIS section-4 alarms (default on).** `enable_cloudwatch_logs = true` delivers
the trail to a CloudWatch Logs group and creates the full CIS AWS v3/v5
metric-filter set, 4.1 to 4.15: unauthorized API calls, console sign-in without
MFA, root usage, IAM policy, CloudTrail config, console auth failures, CMK
disable/deletion, S3 bucket policy, Config, security group, NACL, network
gateway, route table, VPC and Organizations changes. Alarms publish to a
KMS-encrypted SNS topic (`alarm_subscriptions`). The feature works without
extra inputs: when `cloudwatch_logs_kms_key_arn` is null, a dedicated, rotated
CMK is created. Its key policy grants `logs.<region>.amazonaws.com`, scoped by
`kms:EncryptionContext:aws:logs:arn`, and `cloudwatch.amazonaws.com`. The trail's
S3 CMK is never reused, because it lives in the log-archive account. Skip noisy
alarms with `cis_alarms_excluded`.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_cloudtrail.org (modules/aws/security/cloudtrail-org/main.tf#L57)
- resource.aws_cloudwatch_log_group.trail (modules/aws/security/cloudtrail-org/main.tf#L204)
- resource.aws_cloudwatch_log_metric_filter.cis (modules/aws/security/cloudtrail-org/main.tf#L359)
- resource.aws_cloudwatch_metric_alarm.cis (modules/aws/security/cloudtrail-org/main.tf#L371)
- resource.aws_iam_role.cloudtrail_cw (modules/aws/security/cloudtrail-org/main.tf#L212)
- resource.aws_iam_role_policy.cloudtrail_cw (modules/aws/security/cloudtrail-org/main.tf#L229)
- resource.aws_kms_alias.cloudwatch (modules/aws/security/cloudtrail-org/main.tf#L198)
- resource.aws_kms_key.cloudwatch (modules/aws/security/cloudtrail-org/main.tf#L189)
- resource.aws_sns_topic.cis_alarms (modules/aws/security/cloudtrail-org/main.tf#L250)
- resource.aws_sns_topic_policy.cis_alarms (modules/aws/security/cloudtrail-org/main.tf#L257)
- resource.aws_sns_topic_subscription.cis_alarms (modules/aws/security/cloudtrail-org/main.tf#L275)
- data source.aws_caller_identity.current (modules/aws/security/cloudtrail-org/main.tf#L27)
- data source.aws_partition.current (modules/aws/security/cloudtrail-org/main.tf#L29)
- data source.aws_region.current (modules/aws/security/cloudtrail-org/main.tf#L28)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt the CloudTrail log files delivered to the Log-Archive bucket. | `string` | n/a | yes |
| <a name="input_log_archive_bucket"></a> [log\_archive\_bucket](#input\_log\_archive\_bucket) | Name of the central Log-Archive S3 bucket that receives the trail's log files. This bucket lives in the Log-Archive account (a different account from the trail owner); its resource policy authorizes CloudTrail delivery. | `string` | n/a | yes |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | Optional existing SNS topic ARN for CIS alarm notifications. Null (default) = the module creates a KMS-encrypted topic (<trail\_name>-cis-alarms) and subscribes alarm\_subscriptions to it. | `string` | `null` | no |
| <a name="input_alarm_subscriptions"></a> [alarm\_subscriptions](#input\_alarm\_subscriptions) | Subscribers of the module-created CIS alarm SNS topic, keyed by an arbitrary name (ignored when alarm\_sns\_topic\_arn is supplied). Email subscriptions must be confirmed by the recipient. | <pre>map(object({<br/>    protocol = string<br/>    endpoint = string<br/>  }))</pre> | `{}` | no |
| <a name="input_cis_alarms_excluded"></a> [cis\_alarms\_excluded](#input\_cis\_alarms\_excluded) | Keys of CIS metric-filter alarms to skip (e.g. ["unauthorized-api-calls"] if it is too noisy org-wide). Valid keys: unauthorized-api-calls, console-signin-without-mfa, root-account-usage, iam-policy-changes, cloudtrail-config-changes, console-auth-failures, cmk-disable-or-deletion, s3-bucket-policy-changes, config-changes, security-group-changes, nacl-changes, network-gateway-changes, route-table-changes, vpc-changes, organizations-changes. | `list(string)` | `[]` | no |
| <a name="input_cis_metric_namespace"></a> [cis\_metric\_namespace](#input\_cis\_metric\_namespace) | CloudWatch metric namespace for the CIS metric filters. | `string` | `"CISBenchmark"` | no |
| <a name="input_cloudtrail_s3_data_events"></a> [cloudtrail\_s3\_data\_events](#input\_cloudtrail\_s3\_data\_events) | S3 object-level data events recorded by the org trail via advanced event selectors: none, write (CIS AWS 3.8, default), read (CIS 3.9) or all (3.8 + 3.9). COST: data events are billed per event across EVERY org account; read/all on busy buckets can be expensive. | `string` | `"write"` | no |
| <a name="input_cloudwatch_logs_kms_key_admin_arn"></a> [cloudwatch\_logs\_kms\_key\_admin\_arn](#input\_cloudwatch\_logs\_kms\_key\_admin\_arn) | Principal granted administration of the module-created CloudWatch Logs CMK. Null (default) = the trail account's root (delegates to IAM policies, the AWS default key policy) so the key cannot be orphaned. | `string` | `null` | no |
| <a name="input_cloudwatch_logs_kms_key_arn"></a> [cloudwatch\_logs\_kms\_key\_arn](#input\_cloudwatch\_logs\_kms\_key\_arn) | Optional existing CMK ARN for the CloudWatch Logs group AND the CIS alarm SNS topic. Its key policy MUST grant logs.<region>.amazonaws.com (encryption context arn:aws:logs:<region>:<account>:log-group:*) and cloudwatch.amazonaws.com (kms:Decrypt, kms:GenerateDataKey*). Null (default) = the module creates a dedicated, rotated CMK with exactly those grants. | `string` | `null` | no |
| <a name="input_cloudwatch_logs_retention_days"></a> [cloudwatch\_logs\_retention\_days](#input\_cloudwatch\_logs\_retention\_days) | Retention (days) for the CloudWatch Logs group when enable\_cloudwatch\_logs = true. The S3 log archive remains the long-term record. | `number` | `365` | no |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Attach a CloudWatch Logs group to the org trail and create the CIS AWS section-4 metric-filter alarms (4.1-4.15) with a KMS-encrypted SNS topic. Self-sufficient by default: a logs-granted CMK is created when cloudwatch\_logs\_kms\_key\_arn is null. Set false for S3-only delivery. | `bool` | `true` | no |
| <a name="input_enable_lambda_data_events"></a> [enable\_lambda\_data\_events](#input\_enable\_lambda\_data\_events) | Record Lambda Invoke data events (AWS::Lambda::Function) on the org trail. Default false — per-invocation billing can be significant for high-throughput functions. | `bool` | `false` | no |
| <a name="input_exclude_log_archive_bucket_from_data_events"></a> [exclude\_log\_archive\_bucket\_from\_data\_events](#input\_exclude\_log\_archive\_bucket\_from\_data\_events) | Exclude the log-archive bucket (log\_archive\_bucket) from S3 data events so CloudTrail does not record its own log deliveries (a self-amplifying loop). Default true. | `bool` | `true` | no |
| <a name="input_s3_data_events_excluded_bucket_arns"></a> [s3\_data\_events\_excluded\_bucket\_arns](#input\_s3\_data\_events\_excluded\_bucket\_arns) | Additional S3 bucket ARNs (arn:aws:s3:::name) excluded from S3 data events, e.g. high-volume access-log or Security Lake buckets. Matched as a resources.ARN NotStartsWith prefix. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the module's taggable resources (CMK, log group, IAM role, SNS topic, alarms). | `map(string)` | `{}` | no |
| <a name="input_trail_name"></a> [trail\_name](#input\_trail\_name) | Name of the organization CloudTrail trail. | `string` | `"org-trail"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cis_alarm_names"></a> [cis\_alarm\_names](#output\_cis\_alarm\_names) | Map of CIS alarm key -> CloudWatch alarm name. |
| <a name="output_cis_alarm_sns_topic_arn"></a> [cis\_alarm\_sns\_topic\_arn](#output\_cis\_alarm\_sns\_topic\_arn) | SNS topic the CIS alarms publish to (module-created or supplied; null when disabled). |
| <a name="output_cis_metric_filter_patterns"></a> [cis\_metric\_filter\_patterns](#output\_cis\_metric\_filter\_patterns) | Map of CIS alarm key -> { cis\_id, pattern } for every metric filter created. |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudTrail CloudWatch Logs group (null when enable\_cloudwatch\_logs = false). |
| <a name="output_cloudwatch_logs_kms_key_arn"></a> [cloudwatch\_logs\_kms\_key\_arn](#output\_cloudwatch\_logs\_kms\_key\_arn) | CMK encrypting the CloudWatch Logs group and the CIS alarm topic (module-created or supplied; null when disabled). |
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
