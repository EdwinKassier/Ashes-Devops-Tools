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
	budget_currency = 
	customer_id = 
	default_region = 
	domain = 
	environments = 
	monthly_budget_amount = 
	org_id = 
	organization_admin_groups = 
	project_prefix = 
	strict_folder_policy_environment_keys = 
	terraform_admin_email = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |

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
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | Email address of the primary administrator | `string` | n/a | yes |
| <a name="input_admin_project_id"></a> [admin\_project\_id](#input\_admin\_project\_id) | The project ID of the bootstrap admin project | `string` | n/a | yes |
| <a name="input_admin_project_number"></a> [admin\_project\_number](#input\_admin\_project\_number) | The numeric project number of the bootstrap admin project (digits only) | `string` | n/a | yes |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | List of GCP regions permitted by resource location org policy | `list(string)` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | The GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX | `string` | n/a | yes |
| <a name="input_billing_admin_groups"></a> [billing\_admin\_groups](#input\_billing\_admin\_groups) | List of Google Group email addresses to grant billing admin roles | `list(string)` | n/a | yes |
| <a name="input_budget_currency"></a> [budget\_currency](#input\_budget\_currency) | ISO 4217 currency code for the budget (e.g., USD, EUR, GBP) | `string` | n/a | yes |
| <a name="input_customer_id"></a> [customer\_id](#input\_customer\_id) | The Google Workspace customer ID (format: 'C' followed by alphanumerics, e.g., 'C0abc1234') | `string` | n/a | yes |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default GCP region for regional resources (e.g., 'us-central1', 'europe-west1') | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | The primary domain of the GCP organization (e.g., 'example.com') | `string` | n/a | yes |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of environment definitions keyed by environment name (e.g., dev, staging, prod) | <pre>map(object({<br/>    display_name            = string<br/>    description             = string<br/>    iam_group_role_bindings = map(set(string))<br/>  }))</pre> | n/a | yes |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly budget cap in the configured currency. Set to 0 to disable budget alerts (no Budget resource will be created). Must be >= 0. | `number` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The numeric GCP organization ID (digits only, no 'organizations/' prefix) | `string` | n/a | yes |
| <a name="input_organization_admin_groups"></a> [organization\_admin\_groups](#input\_organization\_admin\_groups) | List of Google Group email addresses to grant organization admin roles | `list(string)` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix applied to all project IDs to ensure global uniqueness (lowercase letters, digits, hyphens; starts with letter) | `string` | n/a | yes |
| <a name="input_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#input\_strict\_folder\_policy\_environment\_keys) | Subset of environment keys that enforce strict resource location policies | `list(string)` | n/a | yes |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | Email address of the Terraform admin service account | `string` | n/a | yes |
| <a name="input_billing_contact_email"></a> [billing\_contact\_email](#input\_billing\_contact\_email) | Email address for billing notifications and budget alerts via Essential Contacts. Optional — if null, no Essential Contact is registered for the BILLING category. | `string` | `null` | no |
| <a name="input_break_glass_user"></a> [break\_glass\_user](#input\_break\_glass\_user) | Optional email address of a break-glass emergency user granted org admin access | `string` | `null` | no |
| <a name="input_security_contact_email"></a> [security\_contact\_email](#input\_security\_contact\_email) | Email address for security notifications via Essential Contacts (SCC alerts, compliance notifications). Optional — if null, no Essential Contact is registered for the SECURITY category. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_folders"></a> [folders](#output\_folders) | Map of created folders |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | Organization ID |
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Tag keys available to downstream consumers |
| <a name="output_tag_value_ids"></a> [tag\_value\_ids](#output\_tag\_value\_ids) | Tag values available to downstream consumers |
| <a name="output_tags"></a> [tags](#output\_tags) | Deprecated alias for downstream tag values |
<!-- END_TF_DOCS -->
