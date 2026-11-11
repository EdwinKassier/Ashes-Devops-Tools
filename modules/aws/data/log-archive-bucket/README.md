# log-archive-bucket

Hardened central log-archive S3 bucket for the SRA landing zone — the org-wide
sink for CloudTrail, Config, and Security Lake log delivery. Created with S3
Object Lock, Block Public Access on all four dimensions, versioning, SSE-KMS
with a bucket key, a default Object Lock retention, a GLACIER-transition +
expiration lifecycle, and a bucket policy (built with `jsonencode()`) that scopes
log-delivery grants to this organization via `aws:SourceOrgID` and denies
non-TLS access. With `cloudtrail_trail_account_id` set, the CloudTrail grants
also require `aws:SourceArn` to match a trail in that account
(`arn:<partition>:cloudtrail:*:<id>:trail/*`).

## Server access logs

S3 does not deliver server access logs to a bucket with SSE-KMS default
encryption or an Object Lock default retention, so the archive never logs to
itself. By default the module creates `<log_archive_bucket_name>-access-logs`
(SSE-S3, versioned, no Object Lock, Block Public Access, bucket-owner-enforced,
expiry after `access_log_retention_days`) whose policy lets only
`logging.s3.amazonaws.com` write, only for this archive. Set
`access_log_bucket` to use an existing bucket instead.

## Deletion guard

`enable_deletion_protection` (default `true`) adds a `terraform_data` guard with
`prevent_destroy` and `replace_triggered_by` on the bucket, so a plan that
destroys or replaces the archive fails. Turning the flag off does not remove an
existing guard; run
`terraform state rm '<module_address>.terraform_data.deletion_guard[0]'` first.

## Object Lock and teardown

`object_lock_enabled` is set at bucket creation and is **immutable** afterward —
it cannot be toggled on an existing bucket.

The default retention `mode` is **COMPLIANCE**: a write-once-read-many (WORM)
lock that no principal — including the account root — can shorten or bypass, and
that blocks `terraform destroy` until every object's retention period has
lapsed. See the teardown runbook before attempting to delete a COMPLIANCE
bucket. **GOVERNANCE** mode is opt-in and can be bypassed by principals holding
`s3:BypassGovernanceRetention`.

`log_archive_bucket_name` is a cross-root naming contract: it must match the
deterministic name the B3 SCP references, so keep the two in sync.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	kms_key_arn =
	log_archive_bucket_name =
	org_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |



## Resources

The following resources are created:


- resource.aws_s3_bucket.access_logs (modules/aws/data/log-archive-bucket/main.tf#L233)
- resource.aws_s3_bucket.this (modules/aws/data/log-archive-bucket/main.tf#L115)
- resource.aws_s3_bucket_lifecycle_configuration.access_logs (modules/aws/data/log-archive-bucket/main.tf#L290)
- resource.aws_s3_bucket_lifecycle_configuration.this (modules/aws/data/log-archive-bucket/main.tf#L187)
- resource.aws_s3_bucket_logging.this (modules/aws/data/log-archive-bucket/main.tf#L155)
- resource.aws_s3_bucket_object_lock_configuration.this (modules/aws/data/log-archive-bucket/main.tf#L176)
- resource.aws_s3_bucket_ownership_controls.access_logs (modules/aws/data/log-archive-bucket/main.tf#L261)
- resource.aws_s3_bucket_policy.access_logs (modules/aws/data/log-archive-bucket/main.tf#L314)
- resource.aws_s3_bucket_policy.this (modules/aws/data/log-archive-bucket/main.tf#L214)
- resource.aws_s3_bucket_public_access_block.access_logs (modules/aws/data/log-archive-bucket/main.tf#L251)
- resource.aws_s3_bucket_public_access_block.this (modules/aws/data/log-archive-bucket/main.tf#L134)
- resource.aws_s3_bucket_server_side_encryption_configuration.access_logs (modules/aws/data/log-archive-bucket/main.tf#L279)
- resource.aws_s3_bucket_server_side_encryption_configuration.this (modules/aws/data/log-archive-bucket/main.tf#L164)
- resource.aws_s3_bucket_versioning.access_logs (modules/aws/data/log-archive-bucket/main.tf#L270)
- resource.aws_s3_bucket_versioning.this (modules/aws/data/log-archive-bucket/main.tf#L143)
- resource.terraform_data.deletion_guard (modules/aws/data/log-archive-bucket/main.tf#L359)
- data source.aws_caller_identity.current (modules/aws/data/log-archive-bucket/main.tf#L231)
- data source.aws_partition.current (modules/aws/data/log-archive-bucket/partition.tf#L4)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the CMK used for SSE-KMS default encryption on the bucket (e.g. the aws/kms-key module's key\_arn output). | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Deterministic name of the central log-archive bucket. This is a cross-root naming contract: it must match the name the B3 SCP references. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Used in the aws:SourceOrgID condition that scopes log-delivery grants in the bucket policy. | `string` | n/a | yes |
| <a name="input_access_log_bucket"></a> [access\_log\_bucket](#input\_access\_log\_bucket) | Existing bucket to receive the log archive's S3 server access logs (it must not use SSE-KMS default encryption or an Object Lock default retention). Empty (default) creates a companion <log\_archive\_bucket\_name>-access-logs bucket with SSE-S3 and no Object Lock. | `string` | `""` | no |
| <a name="input_access_log_prefix"></a> [access\_log\_prefix](#input\_access\_log\_prefix) | Key prefix for S3 server access logs. | `string` | `"s3-access-logs/"` | no |
| <a name="input_access_log_retention_days"></a> [access\_log\_retention\_days](#input\_access\_log\_retention\_days) | Days the companion access-log bucket keeps S3 server access logs before they expire. Ignored when access\_log\_bucket names an existing bucket. | `number` | `365` | no |
| <a name="input_cloudtrail_trail_account_id"></a> [cloudtrail\_trail\_account\_id](#input\_cloudtrail\_trail\_account\_id) | Account ID that owns the organization trail (the management account, also when a CloudTrail delegated administrator manages the trail). When set, the CloudTrail grants also require aws:SourceArn to match arn:<partition>:cloudtrail:*:<id>:trail/*. Empty (default) scopes them by aws:SourceOrgID only. | `string` | `""` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Create a prevent\_destroy guard that makes any plan which destroys or replaces the log-archive bucket fail. Turning it off does not remove an existing guard: run terraform state rm on the guard first. | `bool` | `true` | no |
| <a name="input_object_lock_mode"></a> [object\_lock\_mode](#input\_object\_lock\_mode) | Default S3 Object Lock retention mode. COMPLIANCE is WORM against all principals (incl. root) and blocks destroy until retention lapses; GOVERNANCE is bypassable by privileged principals. | `string` | `"COMPLIANCE"` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Default Object Lock retention period, in days. Also drives lifecycle expiration. | `number` | `365` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_log_bucket_name"></a> [access\_log\_bucket\_name](#output\_access\_log\_bucket\_name) | The bucket that receives the log archive's S3 server access logs: the companion <name>-access-logs bucket, or access\_log\_bucket when set. |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | The ARN of the log-archive bucket. |
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | The name (ID) of the log-archive bucket. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | The deterministic bucket name (equals var.log\_archive\_bucket\_name); the cross-root naming contract the B3 SCP references. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "log_archive_bucket" {
  source = "../../modules/aws/log-archive-bucket"

  log_archive_bucket_name = "acme-org-log-archive"
  kms_key_arn             = module.log_kms_key.key_arn
  org_id                  = "o-abc123xyz0"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
