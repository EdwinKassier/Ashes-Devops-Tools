# log-archive-bucket

Hardened central log-archive S3 bucket for the SRA landing zone — the org-wide
sink for CloudTrail, Config, and Security Lake log delivery. Created with S3
Object Lock, Block Public Access on all four dimensions, versioning, SSE-KMS
with a bucket key, a default Object Lock retention, a GLACIER-transition +
expiration lifecycle, and a bucket policy (built with `jsonencode()`) that scopes
log-delivery grants to this organization via `aws:SourceOrgID` and denies
non-TLS access.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_s3_bucket.this (modules/aws/log-archive-bucket/main.tf#L76)
- resource.aws_s3_bucket_lifecycle_configuration.this (modules/aws/log-archive-bucket/main.tf#L123)
- resource.aws_s3_bucket_object_lock_configuration.this (modules/aws/log-archive-bucket/main.tf#L112)
- resource.aws_s3_bucket_policy.this (modules/aws/log-archive-bucket/main.tf#L143)
- resource.aws_s3_bucket_public_access_block.this (modules/aws/log-archive-bucket/main.tf#L83)
- resource.aws_s3_bucket_server_side_encryption_configuration.this (modules/aws/log-archive-bucket/main.tf#L100)
- resource.aws_s3_bucket_versioning.this (modules/aws/log-archive-bucket/main.tf#L92)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the CMK used for SSE-KMS default encryption on the bucket (e.g. the aws/kms-key module's key\_arn output). | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Deterministic name of the central log-archive bucket. This is a cross-root naming contract: it must match the name the B3 SCP references. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Used in the aws:SourceOrgID condition that scopes log-delivery grants in the bucket policy. | `string` | n/a | yes |
| <a name="input_object_lock_mode"></a> [object\_lock\_mode](#input\_object\_lock\_mode) | Default S3 Object Lock retention mode. COMPLIANCE is WORM against all principals (incl. root) and blocks destroy until retention lapses; GOVERNANCE is bypassable by privileged principals. | `string` | `"COMPLIANCE"` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Default Object Lock retention period, in days. Also drives lifecycle expiration. | `number` | `365` | no |

## Outputs

| Name | Description |
|------|-------------|
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
