# kms-key

Reusable customer-managed KMS key (CMK) sized for cross-account log delivery.
Creates the key (with rotation enabled), an alias, and a key policy built with
`jsonencode()` that grants log-delivery service principals (CloudTrail, Config,
Security Lake) the minimum KMS actions, scoped to this organization by
`aws:SourceOrgID`. A key-administration statement for `key_admin_arn` is always
present to prevent locking the key out of management. It grants management
actions only (no Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant), so
the key admin cannot read protected data; key usage is granted separately via
`key_user_arns`. Set `enable_protection_tag = true` to tag the key
`protected = "true"`, which the organization deny-tamper SCP uses to block
ScheduleKeyDeletion/DisableKey except via break-glass.

The log-service grants deliberately omit `kms:ViaService`: CloudTrail (and
Config/Security Lake) call KMS under their own service principal, not via S3, so
a ViaService condition would deny log delivery. The optional `via_services`
input scopes only the general-usage grant for `key_user_arns`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	alias = 
	key_admin_arn = 
	management_account_id = 
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


- resource.aws_kms_alias.this (modules/aws/data/kms-key/main.tf#L160)
- resource.aws_kms_key.this (modules/aws/data/kms-key/main.tf#L153)
- resource.aws_kms_key_policy.this (modules/aws/data/kms-key/main.tf#L165)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alias"></a> [alias](#input\_alias) | Alias for the CMK, without the "alias/" prefix (the module adds it). Used both for the aws\_kms\_alias name and the key description. | `string` | n/a | yes |
| <a name="input_key_admin_arn"></a> [key\_admin\_arn](#input\_key\_admin\_arn) | ARN of the principal (role/user) granted key ADMINISTRATION on the CMK: management actions only (PutKeyPolicy, Enable/Disable, rotation, tagging, ScheduleKeyDeletion/CancelKeyDeletion, ...), no Encrypt/Decrypt/GenerateDataKey/ReEncrypt and no CreateGrant. REQUIRED to prevent locking the key out of management. Grant usage via key\_user\_arns. | `string` | n/a | yes |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | Organization management (payer) account ID. Used to scope the CloudTrail EncryptionContext condition to trails in that account. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Used in the aws:SourceOrgID condition that scopes log-service grants to this org. | `string` | n/a | yes |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Waiting period, in days, before the CMK is deleted after scheduling deletion. AWS permits 7-30. | `number` | `30` | no |
| <a name="input_enable_protection_tag"></a> [enable\_protection\_tag](#input\_enable\_protection\_tag) | Tag the key <protection\_tag\_key> = "true" so the organization deny-tamper SCP blocks ScheduleKeyDeletion/DisableKey/DisableKeyRotation and protection-tag removal except via break-glass. Default false; the security stage enables it for the log-archive, forensics and security-tooling keys. | `bool` | `false` | no |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | Optional list of principal ARNs granted key USAGE (Encrypt/Decrypt/ReEncrypt/GenerateDataKey/DescribeKey) on the CMK. Kept separate from key\_admin\_arn, which receives management actions only. Empty by default (no general-usage statement). | `list(string)` | `[]` | no |
| <a name="input_log_service_principals"></a> [log\_service\_principals](#input\_log\_service\_principals) | AWS log-delivery service principals granted GenerateDataKey/Decrypt/DescribeKey on the CMK, scoped by aws:SourceOrgID. CloudTrail additionally gets an EncryptionContext condition. | `list(string)` | <pre>[<br/>  "cloudtrail.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "securitylake.amazonaws.com"<br/>]</pre> | no |
| <a name="input_protection_tag_key"></a> [protection\_tag\_key](#input\_protection\_tag\_key) | Tag key used when enable\_protection\_tag is true. Must match the organization-policy module's kms\_protection\_tag\_key. | `string` | `"protected"` | no |
| <a name="input_service_principals"></a> [service\_principals](#input\_service\_principals) | Optional list of AWS service principals (e.g. sns.amazonaws.com, ssm.amazonaws.com, cloudwatch.amazonaws.com) granted general-usage (Encrypt/Decrypt/GenerateDataKey/etc.) on the CMK, scoped by aws:SourceOrgID so only calls originating within this org can use the key. Unlike log\_service\_principals these carry no CloudTrail EncryptionContext condition. Empty by default (no service-principal statement). | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to the CMK. | `map(string)` | `{}` | no |
| <a name="input_via_services"></a> [via\_services](#input\_via\_services) | Optional list of kms:ViaService values that scope the general-usage grant for key\_user\_arns (e.g. s3.eu-west-1.amazonaws.com). Never applied to the log-service grants. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | The ARN of the CMK alias. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | The ARN of the CMK. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | The globally unique identifier (key ID) of the CMK. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "log_kms_key" {
  source = "../../modules/aws/kms-key"

  alias                 = "central-logs"
  org_id                = "o-abc123xyz0"
  management_account_id = "111122223333"
  key_admin_arn         = "arn:aws:iam::111122223333:role/KeyAdmin"

  # Defaults cover CloudTrail, Config, and Security Lake log delivery.
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
