# org-security-service

Map-gated org-security service enablement for the SRA landing zone.

Macie, Inspector, Detective and Resource Explorer all share the same
organization-enablement shape: register the delegated administrator from the
**management account**, then configure the service (and turn on auto-enable for
new member accounts) from the delegated-administrator (**Security Tooling**)
account. This module is the generic-ish collapse of those near-identical
setups.

Terraform cannot dynamically switch resource **types**, so rather than one
parameterised resource the module contains a gated block per service, toggled by
membership in `var.enabled_services`:

```hcl
count = contains(var.enabled_services, "<name>") ? 1 : 0
```

**Add a service = add a gated block in `main.tf` + add its name to the allowed
set in `variables.tf`.**

## Providers

The module spans two accounts via two providers:

- The **default** provider is the delegated-administrator account (Security
  Tooling). It owns the service accounts / graphs / indexes and the organization
  configurations.
- The aliased **`aws.management`** provider is the organization management
  account. It owns only the delegated-admin registrations, which must be
  performed from the management account.

## Supported services

| Service | Gate name | Resources |
|---------|-----------|-----------|
| Macie | `macie` | `aws_macie2_account`, `aws_macie2_organization_admin_account` (mgmt), `aws_macie2_organization_configuration` (`auto_enable = true`) |
| Inspector | `inspector` | `aws_inspector2_delegated_admin_account` (mgmt), `aws_inspector2_organization_configuration` (`auto_enable { ec2 ecr lambda }`), `aws_inspector2_enabler` (admin account's own resource types) |
| Detective | `detective` | `aws_detective_graph`, `aws_detective_organization_admin_account` (mgmt), `aws_detective_organization_configuration` (`auto_enable = true`) — **default OFF per SRA** |
| Resource Explorer | `resource-explorer` | `aws_resourceexplorer2_index` (`type = "AGGREGATOR"`), `aws_resourceexplorer2_view` |

Notes:

- `enabled_services` defaults to `["macie", "inspector"]`. Detective is off by
  default per SRA guidance.
- The delegated-admin registration for `resource-explorer-2` is handled by the
  `aws/security-delegated-admin` module, **not** here. This module only creates
  the aggregator index and default view.
- In aws provider v6, `aws_inspector2_organization_configuration.auto_enable` is
  a nested **block** (list, exactly one), so it uses block syntax rather than an
  assignment; `ec2` and `ecr` are required, `lambda` is optional.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
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


- resource.aws_detective_graph.this (modules/aws/org-security-service/main.tf#L89)
- resource.aws_detective_organization_admin_account.this (modules/aws/org-security-service/main.tf#L94)
- resource.aws_detective_organization_configuration.this (modules/aws/org-security-service/main.tf#L100)
- resource.aws_inspector2_delegated_admin_account.this (modules/aws/org-security-service/main.tf#L55)
- resource.aws_inspector2_enabler.this (modules/aws/org-security-service/main.tf#L77)
- resource.aws_inspector2_organization_configuration.this (modules/aws/org-security-service/main.tf#L61)
- resource.aws_macie2_account.this (modules/aws/org-security-service/main.tf#L32)
- resource.aws_macie2_organization_admin_account.this (modules/aws/org-security-service/main.tf#L37)
- resource.aws_macie2_organization_configuration.this (modules/aws/org-security-service/main.tf#L43)
- resource.aws_resourceexplorer2_index.this (modules/aws/org-security-service/main.tf#L115)
- resource.aws_resourceexplorer2_view.this (modules/aws/org-security-service/main.tf#L120)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling account nominated as the delegated administrator (the module's default provider). Used as the admin/account ID in the management-account registrations. | `string` | n/a | yes |
| <a name="input_enabled_services"></a> [enabled\_services](#input\_enabled\_services) | Set of org-security services to enable. Each enables a gated block: macie, inspector, detective, resource-explorer. Detective defaults OFF per SRA. Adding a service means adding a gated block in main.tf and a name to this allowed set. | `set(string)` | <pre>[<br/>  "macie",<br/>  "inspector"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_detective_graph_arn"></a> [detective\_graph\_arn](#output\_detective\_graph\_arn) | The Detective behavior graph ARN, or null when Detective is not enabled. |
| <a name="output_enabled_services"></a> [enabled\_services](#output\_enabled\_services) | The set of org-security services enabled by this module (echo of the input). |
| <a name="output_macie_account_id"></a> [macie\_account\_id](#output\_macie\_account\_id) | The Macie account ID in the Security Tooling account, or null when Macie is not enabled. |
| <a name="output_resource_explorer_index_arn"></a> [resource\_explorer\_index\_arn](#output\_resource\_explorer\_index\_arn) | The Resource Explorer aggregator index ARN, or null when Resource Explorer is not enabled. |
<!-- END_TF_DOCS -->
