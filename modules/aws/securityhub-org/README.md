# securityhub-org

Org-wide AWS Security Hub with **CENTRAL configuration** for the SRA landing
zone. The delegated administrator (Security Tooling account) owns the Security
Hub account enablement, the finding aggregator, the organization configuration,
and the baseline configuration policy; the organization **management** account
(aliased provider) owns only the delegated-admin registration.

Key constraints:

- The delegated admin must be a **MEMBER** account (Security Tooling), **not**
  the management account.
- CENTRAL configuration requires `auto_enable = false`,
  `auto_enable_standards = "NONE"`, and a **pre-existing finding aggregator** —
  the module creates the aggregator first and enforces ordering via `depends_on`.
- This is the mature CSPM path. Security Hub **V2** (unified security posture) is
  a future migration and is intentionally not modelled here.

The baseline policy enables FSBP + CIS 1.4 + NIST 800-53 r5 by default (built
from `home_region`) and is associated to the organization root.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_root_id = 
	security_tooling_account_id = 
	
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
| <a name="provider_aws.management"></a> [aws.management](#provider\_aws.management) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_securityhub_account.this (modules/aws/securityhub-org/main.tf#L41)
- resource.aws_securityhub_configuration_policy.baseline (modules/aws/securityhub-org/main.tf#L76)
- resource.aws_securityhub_configuration_policy_association.root (modules/aws/securityhub-org/main.tf#L93)
- resource.aws_securityhub_finding_aggregator.this (modules/aws/securityhub-org/main.tf#L54)
- resource.aws_securityhub_organization_admin_account.this (modules/aws/securityhub-org/main.tf#L45)
- resource.aws_securityhub_organization_configuration.this (modules/aws/securityhub-org/main.tf#L63)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_root_id"></a> [org\_root\_id](#input\_org\_root\_id) | The organization root ID (r-xxxx) that the baseline configuration policy is associated with. | `string` | n/a | yes |
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling (MEMBER) account nominated as the Security Hub delegated administrator. Must NOT be the management account. | `string` | n/a | yes |
| <a name="input_disabled_control_identifiers"></a> [disabled\_control\_identifiers](#input\_disabled\_control\_identifiers) | Security control identifiers disabled org-wide by the baseline policy. Security Hub enables all other controls (including newly released ones). | `list(string)` | `[]` | no |
| <a name="input_enabled_standard_arns"></a> [enabled\_standard\_arns](#input\_enabled\_standard\_arns) | Security standard ARNs enabled by the baseline configuration policy. Defaults (when empty) to FSBP + CIS 1.4 + NIST 800-53 r5, built from home\_region. | `list(string)` | `[]` | no |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | Home (aggregation) Region used to build the default region-scoped standard ARNs for enabled\_standard\_arns. | `string` | `"eu-west-2"` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Name of the Security Hub configuration policy. | `string` | `"baseline"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_configuration_policy_id"></a> [configuration\_policy\_id](#output\_configuration\_policy\_id) | The UUID of the baseline Security Hub configuration policy. |
| <a name="output_finding_aggregator_arn"></a> [finding\_aggregator\_arn](#output\_finding\_aggregator\_arn) | The ARN of the Security Hub finding aggregator (ALL\_REGIONS). |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "securityhub_org" {
  source = "../../modules/aws/securityhub-org"

  security_tooling_account_id = "111111111111"
  org_root_id                 = "r-abcd"
  home_region                 = "eu-west-2"

  providers = {
    aws            = aws
    aws.management = aws.management
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
