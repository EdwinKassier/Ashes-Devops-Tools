# access-analyzer-org

Organization-scoped IAM Access Analyzer for the SRA landing zone. Creates two
`ORGANIZATION`-scoped analyzers: an external-access analyzer that surfaces
resources shared outside the organization, and an unused-access analyzer that
flags IAM access unused beyond a configurable age.

> **Delegated administration.** Both analyzers are `ORGANIZATION` scoped, so this
> module is applied with the IAM Access Analyzer delegated-administrator
> provider. Delegated-admin registration for `access-analyzer.amazonaws.com` is
> performed **separately** (in the security-delegated-admin module / stage), **not
> here** — Access Analyzer has no dedicated delegated-admin resource of its own.

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


- resource.aws_accessanalyzer_analyzer.external (modules/aws/access-analyzer-org/main.tf#L14)
- resource.aws_accessanalyzer_analyzer.unused (modules/aws/access-analyzer-org/main.tf#L19)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_external_analyzer_name"></a> [external\_analyzer\_name](#input\_external\_analyzer\_name) | Name of the organization-scoped external-access analyzer. | `string` | `"org-external-access"` | no |
| <a name="input_unused_access_age"></a> [unused\_access\_age](#input\_unused\_access\_age) | Number of days without use after which IAM access is flagged as unused by the unused-access analyzer. | `number` | `90` | no |
| <a name="input_unused_analyzer_name"></a> [unused\_analyzer\_name](#input\_unused\_analyzer\_name) | Name of the organization-scoped unused-access analyzer. | `string` | `"org-unused-access"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_external_analyzer_arn"></a> [external\_analyzer\_arn](#output\_external\_analyzer\_arn) | The ARN of the organization external-access analyzer. |
| <a name="output_unused_analyzer_arn"></a> [unused\_analyzer\_arn](#output\_unused\_analyzer\_arn) | The ARN of the organization unused-access analyzer. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "access_analyzer_org" {
  source = "../../modules/aws/access-analyzer-org"

  # Defaults create org-external-access and org-unused-access analyzers with a
  # 90-day unused-access threshold. Override only when you need different names
  # or a different age.
  unused_access_age = 90
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
