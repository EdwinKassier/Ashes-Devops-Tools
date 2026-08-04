# aws-shared-services stage

Phase-2 orchestration wrapper that composes the org's account-agnostic shared
platform services **entirely in the shared services account**. Like
`aws-network-hub`, this stage uses a **single default `aws` provider** (no
aliases): every child module runs in the same account and region.

Both composed capabilities are **independently gated and off by default** — each
bills from the moment it is enabled, so enable them deliberately per
environment.

Composed children:

- **private_ca** (`private-ca`) — one ACM Private Certificate Authority (`ROOT`
  or `SUBORDINATE`), optionally shared org-wide over RAM so member accounts
  issue certificates from a single CA instead of standing up a per-account CA
  fleet. Gated via `enable_private_ca` (default `false`); RAM sharing is
  controlled by `share_ca_org` and requires `org_arn`. ACM PCA bills a fixed
  monthly charge per CA regardless of usage.
- **secrets_baseline** (`secrets-baseline`) — Secrets Manager secrets, each with
  a resource policy that scopes `GetSecretValue` to principals in the
  organization (`aws:PrincipalOrgID`) and optional per-secret rotation. Gated via
  `enable_secrets_baseline` (default `false`); `org_id` is required when enabled
  and `secrets_kms_key_id` selects a customer-managed KMS key.

The stage exports `ca_arn` (the CA ARN, or `null` when the CA is disabled) and
`secret_arns` (map of secret name to ARN, empty when the baseline is disabled)
for downstream roots and app teams to consume.

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



## Modules


- private_ca - ../../aws/private-ca
- secrets_baseline - ../../aws/secrets-baseline




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ca_common_name"></a> [ca\_common\_name](#input\_ca\_common\_name) | Common name (CN) placed in the CA certificate subject. | `string` | `"org-internal-ca"` | no |
| <a name="input_ca_type"></a> [ca\_type](#input\_ca\_type) | Type of certificate authority. ROOT anchors the hierarchy; SUBORDINATE is signed by a parent CA. | `string` | `"ROOT"` | no |
| <a name="input_enable_private_ca"></a> [enable\_private\_ca](#input\_enable\_private\_ca) | Master switch for the ACM Private CA capability. When false, no CA (and no RAM share) is created. ACM PCA bills a fixed monthly charge per CA from creation, so this defaults to false — enable it deliberately. | `bool` | `false` | no |
| <a name="input_enable_secrets_baseline"></a> [enable\_secrets\_baseline](#input\_enable\_secrets\_baseline) | Master switch for the Secrets Manager baseline capability. When false, no secrets, policies, or rotations are created. | `bool` | `false` | no |
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | ARN of the AWS Organization (arn:aws:organizations::<mgmt-account>:organization/o-xxxx) granted access to the CA's RAM share. Required when both enable\_private\_ca and share\_ca\_org are true. | `string` | `""` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS organization ID (o-xxxxxxxxxx) used in the aws:PrincipalOrgID condition that scopes secret access to the organization. Required when enable\_secrets\_baseline is true. | `string` | `""` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Map of secret name to its configuration. rotation\_lambda\_arn, when set, enables automatic rotation for that secret; rotation\_days controls the rotation interval. | <pre>map(object({<br/>    rotation_lambda_arn = optional(string, "")<br/>    rotation_days       = optional(number, 30)<br/>  }))</pre> | `{}` | no |
| <a name="input_secrets_kms_key_id"></a> [secrets\_kms\_key\_id](#input\_secrets\_kms\_key\_id) | ARN or ID of a customer-managed KMS key used to encrypt all secrets. When empty, secrets use the account default aws/secretsmanager managed key. | `string` | `""` | no |
| <a name="input_share_ca_org"></a> [share\_ca\_org](#input\_share\_ca\_org) | Whether to share the CA across the AWS organization via RAM so member accounts can issue certificates from it. Requires org\_arn when true. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ca_arn"></a> [ca\_arn](#output\_ca\_arn) | ARN of the ACM Private CA, or null when the Private CA capability is disabled. |
| <a name="output_secret_arns"></a> [secret\_arns](#output\_secret\_arns) | Map of secret name to its ARN. Empty when the Secrets Manager baseline is disabled. |
<!-- END_TF_DOCS -->
