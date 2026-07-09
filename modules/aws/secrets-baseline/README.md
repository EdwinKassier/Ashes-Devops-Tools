# secrets-baseline

Organization Secrets Manager baseline for the SRA landing zone. Creates a set of
secrets, each with a resource policy that scopes `secretsmanager:GetSecretValue`
to principals in the organization via the `aws:PrincipalOrgID` condition.
Secrets that supply a rotation Lambda ARN get automatic rotation wired up. All
secrets are KMS-encrypted — with a customer-managed key when `kms_key_id` is
provided, otherwise with the account default `aws/secretsmanager` key.

**Gated (default off).** `enable_secrets_baseline` defaults to `false`; no
resources are created while disabled.

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


- resource.aws_secretsmanager_secret.this (modules/aws/secrets-baseline/main.tf#L13)
- resource.aws_secretsmanager_secret_policy.this (modules/aws/secrets-baseline/main.tf#L28)
- resource.aws_secretsmanager_secret_rotation.this (modules/aws/secrets-baseline/main.tf#L49)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_secrets_baseline"></a> [enable\_secrets\_baseline](#input\_enable\_secrets\_baseline) | Master switch for the module. When false, no secrets, policies, or rotations are created. | `bool` | `false` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | ARN or ID of a customer-managed KMS key used to encrypt all secrets. When empty, secrets use the account default aws/secretsmanager managed key. | `string` | `""` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS organization ID (o-xxxxxxxxxx) used in the aws:PrincipalOrgID condition that scopes secret access to the organization. Required when enable\_secrets\_baseline is true. | `string` | `""` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Map of secret name to its configuration. rotation\_lambda\_arn, when set, enables automatic rotation for that secret; rotation\_days controls the rotation interval. | <pre>map(object({<br/>    rotation_lambda_arn = optional(string, "")<br/>    rotation_days       = optional(number, 30)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_secret_arns"></a> [secret\_arns](#output\_secret\_arns) | Map of secret name to its ARN. Empty when the module is disabled. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "secrets_baseline" {
  source = "../../modules/aws/secrets-baseline"

  enable_secrets_baseline = true
  org_id                  = "o-exampleorgid"
  kms_key_id              = "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"

  secrets = {
    "app/db-password" = {}
    "app/api-key" = {
      rotation_lambda_arn = "arn:aws:lambda:us-east-1:111122223333:function:rotate"
      rotation_days       = 30
    }
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
