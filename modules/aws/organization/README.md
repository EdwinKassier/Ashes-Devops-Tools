# organization

AWS Organizations control plane for the SRA landing zone. Creates the
organization with `feature_set = "ALL"`, the SRA OU tree (top-level plus child
OUs), enabled organization policy types, and trusted service access for the SRA
security service set.

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


- resource.aws_organizations_organization.this (modules/aws/organization/main.tf#L12)
- resource.aws_organizations_organizational_unit.child (modules/aws/organization/main.tf#L24)
- resource.aws_organizations_organizational_unit.top (modules/aws/organization/main.tf#L18)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_service_access_principals"></a> [aws\_service\_access\_principals](#input\_aws\_service\_access\_principals) | AWS service principals granted trusted access to the organization (enables delegated administration for SRA security services). | `list(string)` | <pre>[<br/>  "cloudtrail.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "config-multiaccountsetup.amazonaws.com",<br/>  "guardduty.amazonaws.com",<br/>  "securityhub.amazonaws.com",<br/>  "access-analyzer.amazonaws.com",<br/>  "malware-protection.guardduty.amazonaws.com",<br/>  "macie.amazonaws.com",<br/>  "inspector2.amazonaws.com",<br/>  "detective.amazonaws.com",<br/>  "ram.amazonaws.com",<br/>  "sso.amazonaws.com",<br/>  "ipam.amazonaws.com",<br/>  "iam.amazonaws.com",<br/>  "ssm.amazonaws.com",<br/>  "resource-explorer-2.amazonaws.com",<br/>  "fms.amazonaws.com",<br/>  "backup.amazonaws.com",<br/>  "securitylake.amazonaws.com"<br/>]</pre> | no |
| <a name="input_child_ous"></a> [child\_ous](#input\_child\_ous) | Child organizational units nested under a top-level OU. Each parent must appear in top\_level\_ous. | <pre>list(object({<br/>    parent = string # Name of the top-level OU this child is nested under (must be in top_level_ous)<br/>    name   = string # Name of the child OU<br/>  }))</pre> | <pre>[<br/>  {<br/>    "name": "Prod",<br/>    "parent": "Workloads"<br/>  },<br/>  {<br/>    "name": "NonProd",<br/>    "parent": "Workloads"<br/>  }<br/>]</pre> | no |
| <a name="input_enabled_policy_types"></a> [enabled\_policy\_types](#input\_enabled\_policy\_types) | Organization policy types to enable at the root. Requires feature\_set = ALL. | `list(string)` | <pre>[<br/>  "SERVICE_CONTROL_POLICY",<br/>  "RESOURCE_CONTROL_POLICY",<br/>  "DECLARATIVE_POLICY_EC2",<br/>  "TAG_POLICY",<br/>  "BACKUP_POLICY"<br/>]</pre> | no |
| <a name="input_top_level_ous"></a> [top\_level\_ous](#input\_top\_level\_ous) | Names of the top-level organizational units created directly under the org root. Defaults to the AWS SRA foundational OU set. | `list(string)` | <pre>[<br/>  "Security",<br/>  "Infrastructure",<br/>  "Workloads",<br/>  "Sandbox",<br/>  "Suspended",<br/>  "PolicyStaging",<br/>  "Exceptions",<br/>  "Transitional"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_management_account_id"></a> [management\_account\_id](#output\_management\_account\_id) | The account ID of the organization management (master) account. |
| <a name="output_organization_arn"></a> [organization\_arn](#output\_organization\_arn) | The ARN of the AWS organization. |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | The ID of the AWS organization. |
| <a name="output_ou_ids"></a> [ou\_ids](#output\_ou\_ids) | Map of OU name to OU ID. Top-level OUs are keyed by name; child OUs are keyed by their full "parent/name" path. |
| <a name="output_roots_id"></a> [roots\_id](#output\_roots\_id) | The ID of the organization root, under which the top-level OUs are created. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "organization" {
  source = "../../modules/aws/organization"

  # Defaults already provide the full SRA OU tree, policy types, and trusted
  # service access. Override only when you need a different topology.
  top_level_ous = ["Security", "Infrastructure", "Workloads", "Sandbox"]

  child_ous = [
    { parent = "Workloads", name = "Prod" },
    { parent = "Workloads", name = "NonProd" },
  ]
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
