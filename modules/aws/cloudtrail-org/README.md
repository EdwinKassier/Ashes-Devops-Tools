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


- resource.aws_cloudtrail.org (modules/aws/cloudtrail-org/main.tf#L19)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt the CloudTrail log files delivered to the Log-Archive bucket. | `string` | n/a | yes |
| <a name="input_log_archive_bucket"></a> [log\_archive\_bucket](#input\_log\_archive\_bucket) | Name of the central Log-Archive S3 bucket that receives the trail's log files. This bucket lives in the Log-Archive account (a different account from the trail owner); its resource policy authorizes CloudTrail delivery. | `string` | n/a | yes |
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
