# account-baseline

Per-account security defaults that the declarative EC2 organization policy does
**not** cover.

The declarative EC2 policy governs EC2-service defaults centrally. This module
handles the account/Region-scoped settings that live outside it:

- **Default EBS encryption per Region.** Enabled in every Region in
  `aws_enabled_regions`; optionally pinned to a customer-managed KMS key via
  `kms_key_arn`.
- **Account-level S3 Block Public Access.** All four flags
  (`block_public_acls`, `block_public_policy`, `ignore_public_acls`,
  `restrict_public_buckets`) set to true.
- **IAM account password policy.** CIS-aligned: minimum length (>= 14),
  complexity requirements, rotation age, and reuse prevention.

**Default-VPC deletion is not managed here.** Deleting each account's default
VPC is a one-shot bootstrap action handled by the out-of-band StackSet
(Convention 9), not a continuously-reconciled Terraform setting.

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


- resource.aws_ebs_default_kms_key.this (modules/aws/account-baseline/main.tf#L25)
- resource.aws_ebs_encryption_by_default.this (modules/aws/account-baseline/main.tf#L19)
- resource.aws_iam_account_password_policy.this (modules/aws/account-baseline/main.tf#L38)
- resource.aws_s3_account_public_access_block.this (modules/aws/account-baseline/main.tf#L31)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which to enforce default EBS encryption (and, if set, the default EBS KMS key). Defaults to the single home Region. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the CMK to set as the account default EBS encryption key per Region. Empty string leaves default EBS encryption on the AWS-managed key. | `string` | `""` | no |
| <a name="input_password_max_age"></a> [password\_max\_age](#input\_password\_max\_age) | Maximum age in days before an IAM user password must be rotated. | `number` | `90` | no |
| <a name="input_password_min_length"></a> [password\_min\_length](#input\_password\_min\_length) | Minimum length for IAM user passwords. CIS requires at least 14. | `number` | `14` | no |
| <a name="input_password_reuse_prevention"></a> [password\_reuse\_prevention](#input\_password\_reuse\_prevention) | Number of previous IAM user passwords that cannot be reused. | `number` | `24` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ebs_encryption_regions"></a> [ebs\_encryption\_regions](#output\_ebs\_encryption\_regions) | Regions in which default EBS encryption is enforced. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "account_baseline" {
  source = "../../modules/aws/account-baseline"

  aws_enabled_regions = ["eu-west-2"]
  # kms_key_arn       = "arn:aws:kms:eu-west-2:111111111111:key/..."  # optional CMK
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
