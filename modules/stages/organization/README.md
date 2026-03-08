# Organization Stage Module

Sets up the organizational hierarchy, policies, and centralized governance features.

## Purpose

- **Hierarchy**: Defines the shared-services folder plus one folder per declared environment
- **IAM**: Configures organization-level access (groups, roles)
- **Governance**: Applies organization policies (boolean & list constraints)
- **Auditing**: Sets up centralized Cloud Audit Logs and BigQuery analytics
- **Security**: Configures SCC notifications and essential contacts

## Dependencies

Requires the `bootstrap` stage to be completed first. The Terraform Admin SA created in bootstrap should be used to apply this module.

## Usage

```hcl
module "organization" {
  source = "../../modules/stages/organization"

  org_id          = "123456789"
  billing_account = "000000-000000-000000"
  admin_project_id = "my-org-admin-123"

  # Access Configuration
  admin_email = "admin@example.com"
}
```

## Key Components

1. **Folder Structure**: shared-services plus a declarative environment map
2. **Org Policies**: Security baselines (no public IPs, shielded VMs, etc.)
3. **Audit Logging**: Long-term storage in GCS + Analytics in BigQuery
4. **SCC**: Real-time security finding notifications

## Outputs

- `folders`: Map of created folders
- `organization_id`: Organization ID
- `tag_keys`: Tag keys exposed to downstream consumers
- `tag_value_ids`: Tag values exposed to downstream consumers

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	admin_email = 
	admin_project_id = 
	admin_project_number = 
	allowed_regions = 
	billing_account = 
	billing_admin_groups = 
	billing_contact_email = 
	budget_currency = 
	customer_id = 
	default_region = 
	domain = 
	environments = 
	monthly_budget_amount = 
	org_id = 
	organization_admin_groups = 
	project_prefix = 
	security_contact_email = 
	strict_folder_policy_environment_keys = 
	terraform_admin_email = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |

## Modules


- audit_logs - ../../governance/cloud-audit-logs
- cmek - ../../governance/kms
- org_budget - ../../governance/billing
- org_policies - ../../governance/org-policy
- organization - ../../iam/organization
- prod_folder_policies - ../../governance/org-policy
- scc_notifications - ../../governance/scc
- tags - ../../governance/tags


## Resources

The following resources are created:


- resource.google_bigquery_dataset.billing_export (modules/stages/organization/main.tf#L283)
- resource.google_essential_contacts_contact.billing (modules/stages/organization/main.tf#L256)
- resource.google_essential_contacts_contact.security (modules/stages/organization/main.tf#L247)
- resource.google_folder_iam_member.terraform_admin_folder_roles (modules/stages/organization/main.tf#L27)
- resource.google_tags_tag_binding.environment (modules/stages/organization/tags_binding.tf#L1)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | n/a | `string` | n/a | yes |
| <a name="input_admin_project_id"></a> [admin\_project\_id](#input\_admin\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_admin_project_number"></a> [admin\_project\_number](#input\_admin\_project\_number) | n/a | `string` | n/a | yes |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | n/a | `list(string)` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | n/a | `string` | n/a | yes |
| <a name="input_billing_admin_groups"></a> [billing\_admin\_groups](#input\_billing\_admin\_groups) | n/a | `list(string)` | n/a | yes |
| <a name="input_billing_contact_email"></a> [billing\_contact\_email](#input\_billing\_contact\_email) | n/a | `string` | n/a | yes |
| <a name="input_budget_currency"></a> [budget\_currency](#input\_budget\_currency) | n/a | `string` | n/a | yes |
| <a name="input_customer_id"></a> [customer\_id](#input\_customer\_id) | n/a | `string` | n/a | yes |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | n/a | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | n/a | `string` | n/a | yes |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of environment definitions | <pre>map(object({<br/>    display_name            = string<br/>    description             = string<br/>    iam_group_role_bindings = map(set(string))<br/>  }))</pre> | n/a | yes |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | n/a | `number` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | n/a | `string` | n/a | yes |
| <a name="input_organization_admin_groups"></a> [organization\_admin\_groups](#input\_organization\_admin\_groups) | n/a | `list(string)` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | n/a | `string` | n/a | yes |
| <a name="input_security_contact_email"></a> [security\_contact\_email](#input\_security\_contact\_email) | n/a | `string` | n/a | yes |
| <a name="input_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#input\_strict\_folder\_policy\_environment\_keys) | n/a | `list(string)` | n/a | yes |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | n/a | `string` | n/a | yes |
| <a name="input_break_glass_user"></a> [break\_glass\_user](#input\_break\_glass\_user) | n/a | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_folders"></a> [folders](#output\_folders) | Map of created folders |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | Organization ID |
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Tag keys available to downstream consumers |
| <a name="output_tag_value_ids"></a> [tag\_value\_ids](#output\_tag\_value\_ids) | Tag values available to downstream consumers |
| <a name="output_tags"></a> [tags](#output\_tags) | Deprecated alias for downstream tag values |
<!-- END_TF_DOCS -->
