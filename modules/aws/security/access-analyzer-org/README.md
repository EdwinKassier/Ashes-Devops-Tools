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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_accessanalyzer_analyzer.external (modules/aws/security/access-analyzer-org/main.tf#L21)
- resource.aws_accessanalyzer_analyzer.external_extra (modules/aws/security/access-analyzer-org/main.tf#L33)
- resource.aws_accessanalyzer_analyzer.internal (modules/aws/security/access-analyzer-org/main.tf#L43)
- resource.aws_accessanalyzer_analyzer.internal_extra (modules/aws/security/access-analyzer-org/main.tf#L62)
- resource.aws_accessanalyzer_analyzer.unused (modules/aws/security/access-analyzer-org/main.tf#L82)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_internal_access_analyzer"></a> [enable\_internal\_access\_analyzer](#input\_enable\_internal\_access\_analyzer) | Create the ORGANIZATION\_INTERNAL\_ACCESS analyzer in the home region and every entry of regions. | `bool` | `false` | no |
| <a name="input_external_analyzer_name"></a> [external\_analyzer\_name](#input\_external\_analyzer\_name) | Name of the organization-scoped external-access analyzer. | `string` | `"org-external-access"` | no |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | Region of the provider this module runs with; the unkeyed external/internal analyzers live here. Required when regions is non-empty. | `string` | `""` | no |
| <a name="input_internal_access_resource_types"></a> [internal\_access\_resource\_types](#input\_internal\_access\_resource\_types) | Resource types (e.g. AWS::S3::Bucket) the internal-access analyzer monitors. Empty monitors all supported types. | `list(string)` | `[]` | no |
| <a name="input_internal_analyzer_name"></a> [internal\_analyzer\_name](#input\_internal\_analyzer\_name) | Name of the organization-scoped internal-access analyzer. | `string` | `"org-internal-access"` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Enabled regions to create the external (and, if enabled, internal) analyzers in. Every region other than home\_region gets an analyzer through the resource-level region argument. Empty (default) creates only the home-region analyzers. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |
| <a name="input_unused_access_age"></a> [unused\_access\_age](#input\_unused\_access\_age) | Number of days without use after which IAM access is flagged as unused by the unused-access analyzer. | `number` | `90` | no |
| <a name="input_unused_analyzer_name"></a> [unused\_analyzer\_name](#input\_unused\_analyzer\_name) | Name of the organization-scoped unused-access analyzer. | `string` | `"org-unused-access"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_external_analyzer_arn"></a> [external\_analyzer\_arn](#output\_external\_analyzer\_arn) | The ARN of the organization external-access analyzer. |
| <a name="output_external_analyzer_arns_by_region"></a> [external\_analyzer\_arns\_by\_region](#output\_external\_analyzer\_arns\_by\_region) | Map of region to external-access analyzer ARN for the extra regions (home region: external\_analyzer\_arn). |
| <a name="output_internal_analyzer_arn"></a> [internal\_analyzer\_arn](#output\_internal\_analyzer\_arn) | ARN of the home-region organization internal-access analyzer, or null when disabled. |
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
