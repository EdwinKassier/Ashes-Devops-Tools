# Google Cloud Organization Module

This Terraform module sets up a Google Cloud Organization and configures essential identity and security components. It provides a foundation for managing resources across multiple projects with proper organizational structure and security controls.

## Features

- Configures Google Cloud Organization settings
- Enables essential GCP APIs:
  - Cloud Resource Manager
  - Identity and Access Management (IAM)
  - Cloud Identity
  - Organization Policy
- Sets up organization-level IAM policies
- Implements organization policies for resource location restrictions
- Configures domain-restricted sharing

## Usage

```hcl
module "organization" {
  source = "./modules/iam/organization"

  domain     = "example.com"
  project_id = "my-project-id"
  
  org_admin_members = [
    "user:admin@example.com",
    "group:admins@example.com"
  ]
  
  billing_admin_members = [
    "user:billing@example.com"
  ]
  
  allowed_regions = [
    "europe-west1",
    "europe-west2",
    "us-central1"
  ]
  
  tags = {
    environment = "production"
    managed_by  = "terraform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| google | >= 4.0.0 |
| google-beta | >= 4.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| domain | The domain name of the organization (e.g., 'example.com') | string | - | yes |
| project_id | The project ID to enable services in | string | - | yes |
| customer_id | The customer ID of the Google Cloud organization | string | - | yes |
| org_admin_members | List of members to have organization admin role | list(string) | [] | no |
| billing_admin_members | List of members to have billing admin role | list(string) | [] | no |
| organizational_units | Map of organizational units to create | map(object) | ... | no |
| group_defaults | Map of group keys to list of default members | map(list(string)) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| organization_id | The numeric ID of the organization |
| organization_name | The resource name of the organization |
| organization_directory_customer_id | The directory customer ID of the organization |
| organization_create_time | Timestamp when the organization was created |
| enabled_apis | List of APIs enabled in the organization |

## Security Features

1. Organization-level IAM policies for access control
2. Resource location restrictions
3. Domain-restricted sharing
4. Essential security-related APIs enabled

## Notes

- This module should be applied with organization admin privileges
- Ensure you have appropriate permissions to manage GCP organizations
- The organization must be set up in Cloud Identity before using this module
- Consider reviewing and customizing the organization policies based on your security requirements 

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	customer_id = 
	domain = 
	project_id = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | 6.50.0 |



## Resources

The following resources are created:


- resource.google_folder.ou_folders (modules/iam/organization/main.tf#L38)
- resource.google_folder_iam_member.folder_iam_members (modules/iam/organization/main.tf#L65)
- resource.google_organization_iam_member.billing_admins (modules/iam/organization/main.tf#L30)
- resource.google_organization_iam_member.org_admins (modules/iam/organization/main.tf#L22)
- resource.google_project_service.required_apis (modules/iam/organization/main.tf#L8)
- data source.google_organization.org (modules/iam/organization/main.tf#L3)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_customer_id"></a> [customer\_id](#input\_customer\_id) | The customer ID of the Google Cloud organization (e.g., 'C0abc123') | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | The domain name of the organization (e.g., 'example.com') | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID to enable services in | `string` | n/a | yes |
| <a name="input_billing_admin_members"></a> [billing\_admin\_members](#input\_billing\_admin\_members) | List of members to have billing admin role (format: user:email, group:email, serviceAccount:email, or domain:domain) | `list(string)` | `[]` | no |
| <a name="input_group_defaults"></a> [group\_defaults](#input\_group\_defaults) | Deprecated. Group membership is no longer managed by this module. | `map(list(string))` | `{}` | no |
| <a name="input_org_admin_members"></a> [org\_admin\_members](#input\_org\_admin\_members) | List of members to have organization admin role (format: user:email, group:email, serviceAccount:email, or domain:domain) | `list(string)` | `[]` | no |
| <a name="input_organizational_units"></a> [organizational\_units](#input\_organizational\_units) | Map of organizational units to create | <pre>map(object({<br/>    display_name            = string<br/>    description             = optional(string, "")<br/>    iam_group_role_bindings = optional(map(set(string)), {})<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_enabled_apis"></a> [enabled\_apis](#output\_enabled\_apis) | List of APIs enabled in the organization |
| <a name="output_folder_iam_members"></a> [folder\_iam\_members](#output\_folder\_iam\_members) | Map of folder IAM members |
| <a name="output_folders"></a> [folders](#output\_folders) | Map of created folders |
| <a name="output_group_memberships"></a> [group\_memberships](#output\_group\_memberships) | Deprecated. Group membership is no longer managed by this module. |
| <a name="output_identity_groups"></a> [identity\_groups](#output\_identity\_groups) | Deprecated. Group creation is no longer managed by this module. |
| <a name="output_organization_directory_customer_id"></a> [organization\_directory\_customer\_id](#output\_organization\_directory\_customer\_id) | The directory customer ID of the organization |
| <a name="output_organization_domain"></a> [organization\_domain](#output\_organization\_domain) | The domain of the organization |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | The numeric ID of the organization |
| <a name="output_organization_name"></a> [organization\_name](#output\_organization\_name) | The resource name of the organization |
| <a name="output_organizational_units"></a> [organizational\_units](#output\_organizational\_units) | Map of created organizational units |
<!-- END_TF_DOCS -->