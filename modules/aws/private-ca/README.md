# private-ca

Centralized ACM Private CA hierarchy for the SRA landing zone. Provisions a
single ACM Private Certificate Authority (ROOT or SUBORDINATE) and, optionally,
shares it across the AWS organization via RAM so member accounts issue
certificates from one CA — a material cost saving over a per-account CA fleet,
since ACM PCA bills a fixed monthly charge per CA.

**Gated (default off).** `enable_private_ca` defaults to `false` because a CA
incurs a monthly charge from the moment it is created. No resources — and no
billing — while disabled.

`aws_acmpca_policy` is intentionally omitted: cross-account access is delivered
through the RAM share, and a CA resource policy is not required for the
self-managed, org-shared model this module implements.

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


- resource.aws_acmpca_certificate_authority.this (modules/aws/private-ca/main.tf#L13)
- resource.aws_ram_principal_association.org (modules/aws/private-ca/main.tf#L46)
- resource.aws_ram_resource_association.ca (modules/aws/private-ca/main.tf#L40)
- resource.aws_ram_resource_share.this (modules/aws/private-ca/main.tf#L34)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ca_type"></a> [ca\_type](#input\_ca\_type) | Type of certificate authority. ROOT anchors the hierarchy; SUBORDINATE is signed by a parent CA. | `string` | `"ROOT"` | no |
| <a name="input_common_name"></a> [common\_name](#input\_common\_name) | Common name (CN) placed in the CA certificate subject. | `string` | `"org-internal-ca"` | no |
| <a name="input_enable_private_ca"></a> [enable\_private\_ca](#input\_enable\_private\_ca) | Master switch for the module. When false, no resources are created. ACM Private CA bills a fixed monthly charge per CA from creation, so this defaults to false — enable it deliberately. | `bool` | `false` | no |
| <a name="input_key_algorithm"></a> [key\_algorithm](#input\_key\_algorithm) | Key algorithm used to generate the CA's key pair (e.g. RSA\_4096, EC\_prime256v1). | `string` | `"RSA_4096"` | no |
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | ARN of the AWS organization (or an OU) granted access to the RAM share. Required when share\_org is true. | `string` | `""` | no |
| <a name="input_permanent_deletion_time_in_days"></a> [permanent\_deletion\_time\_in\_days](#input\_permanent\_deletion\_time\_in\_days) | Number of days AWS retains a deleted CA before permanent destruction (recovery window). Must be between 7 and 30. | `number` | `7` | no |
| <a name="input_share_name"></a> [share\_name](#input\_share\_name) | Name of the RAM resource share created when share\_org is true. | `string` | `"private-ca-share"` | no |
| <a name="input_share_org"></a> [share\_org](#input\_share\_org) | Whether to share the CA across the AWS organization via RAM so member accounts can issue certificates from it. | `bool` | `true` | no |
| <a name="input_signing_algorithm"></a> [signing\_algorithm](#input\_signing\_algorithm) | Algorithm the CA uses to sign certificates it issues (e.g. SHA512WITHRSA). | `string` | `"SHA512WITHRSA"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ca_arn"></a> [ca\_arn](#output\_ca\_arn) | ARN of the ACM Private CA, or null when the module is disabled. |
| <a name="output_resource_share_arn"></a> [resource\_share\_arn](#output\_resource\_share\_arn) | ARN of the RAM resource share, or null when sharing is disabled. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "private_ca" {
  source = "../../modules/aws/private-ca"

  enable_private_ca = true
  common_name       = "acme-internal-ca"
  org_arn           = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
