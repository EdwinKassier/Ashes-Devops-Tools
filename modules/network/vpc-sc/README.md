# VPC Service Controls Module

Creates VPC Service Controls perimeters to protect GCP resources from data exfiltration and unauthorized access.

## Features

- Create and manage access policies (org-level)
- Define access levels with IP, identity, device, and geo conditions
- Create regular and bridge service perimeters
- Configure ingress and egress policies
- Restrict GCP API access to perimeter boundaries

## Usage

```hcl
module "vpc_sc" {
  source = "../network/vpc-sc"

  organization_id    = "organizations/123456789"
  access_policy_name = "123456789"  # Existing policy number

  perimeter_name  = "production_perimeter"
  perimeter_title = "Production Data Perimeter"

  protected_projects = [
    "111111111111",  # Project numbers (not IDs)
    "222222222222",
  ]

  restricted_services = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
  ]

  access_levels = [
    {
      name  = "corporate_network"
      title = "Corporate Network Access"
      conditions = [{
        ip_subnetworks = ["10.0.0.0/8", "172.16.0.0/12"]
      }]
    },
    {
      name  = "trusted_identities"
      title = "Trusted Service Accounts"
      conditions = [{
        members = ["serviceAccount:ci-cd@project.iam.gserviceaccount.com"]
      }]
    }
  ]

  ingress_policies = [
    {
      identity_type = "ANY_IDENTITY"
      sources       = [{ access_level = "corporate_network" }]
      operations    = [{ service_name = "storage.googleapis.com" }]
    }
  ]
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| organization_id | Organization ID | string | yes |
| perimeter_name | Name of the perimeter | string | yes |
| perimeter_title | Human-readable title | string | yes |
| protected_projects | Project numbers to protect | list(string) | no |
| restricted_services | GCP services to restrict | list(string) | no |
| access_levels | Access level definitions | list(object) | no |
| ingress_policies | Ingress policy rules | list(object) | no |
| egress_policies | Egress policy rules | list(object) | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the service perimeter |
| self_link | The resource name of the perimeter |
| access_levels | Map of created access levels |
| perimeter | The full perimeter resource |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

VPC Service Controls Module - Main Configuration

Creates service perimeters to protect GCP resources from data exfiltration
and unauthorized access, even from within Google Cloud.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	organization_id = 
	perimeter_name = 
	perimeter_title = 
	
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



## Resources

The following resources are created:


- resource.google_access_context_manager_access_level.levels (modules/network/vpc-sc/main.tf#L29)
- resource.google_access_context_manager_access_policy.policy (modules/network/vpc-sc/main.tf#L14)
- resource.google_access_context_manager_service_perimeter.bridge (modules/network/vpc-sc/main.tf#L277)
- resource.google_access_context_manager_service_perimeter.perimeter (modules/network/vpc-sc/main.tf#L78)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | The organization ID (e.g., 'organizations/123456789') | `string` | n/a | yes |
| <a name="input_perimeter_name"></a> [perimeter\_name](#input\_perimeter\_name) | Name of the service perimeter | `string` | n/a | yes |
| <a name="input_perimeter_title"></a> [perimeter\_title](#input\_perimeter\_title) | Human-readable title for the service perimeter | `string` | n/a | yes |
| <a name="input_access_levels"></a> [access\_levels](#input\_access\_levels) | List of access levels to create | <pre>list(object({<br/>    name               = string<br/>    title              = string<br/>    description        = optional(string)<br/>    combining_function = optional(string, "AND")<br/>    conditions = list(object({<br/>      ip_subnetworks         = optional(list(string))<br/>      required_access_levels = optional(list(string))<br/>      members                = optional(list(string))<br/>      negate                 = optional(bool, false)<br/>      regions                = optional(list(string))<br/>      device_policy = optional(object({<br/>        require_screen_lock              = optional(bool)<br/>        require_admin_approval           = optional(bool)<br/>        require_corp_owned               = optional(bool)<br/>        allowed_encryption_statuses      = optional(list(string))<br/>        allowed_device_management_levels = optional(list(string))<br/>        os_constraints = optional(list(object({<br/>          os_type                    = string<br/>          minimum_version            = optional(string)<br/>          require_verified_chrome_os = optional(bool)<br/>        })))<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_access_policy_name"></a> [access\_policy\_name](#input\_access\_policy\_name) | Existing access policy name (required if create\_access\_policy is false) | `string` | `null` | no |
| <a name="input_access_policy_title"></a> [access\_policy\_title](#input\_access\_policy\_title) | Title for the access policy (if creating new) | `string` | `"Organization Access Policy"` | no |
| <a name="input_create_access_policy"></a> [create\_access\_policy](#input\_create\_access\_policy) | Whether to create a new access policy (only one per org allowed) | `bool` | `false` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the service perimeter | `string` | `"Managed by Terraform"` | no |
| <a name="input_egress_policies"></a> [egress\_policies](#input\_egress\_policies) | Egress policies for the perimeter | <pre>list(object({<br/>    identity_type = optional(string)<br/>    identities    = optional(list(string))<br/>    resources     = optional(list(string))<br/>    operations = optional(list(object({<br/>      service_name = string<br/>      method_selectors = optional(list(object({<br/>        method     = optional(string)<br/>        permission = optional(string)<br/>      })))<br/>    })))<br/>  }))</pre> | `[]` | no |
| <a name="input_enable_dry_run"></a> [enable\_dry\_run](#input\_enable\_dry\_run) | Enable dry run mode for the service perimeter.<br/>When enabled, VPC-SC violations are logged but not enforced.<br/>This is recommended for initial rollout to identify potential issues before enforcement.<br/><br/>Set to false once you've verified no unexpected violations occur. | `bool` | `false` | no |
| <a name="input_ingress_policies"></a> [ingress\_policies](#input\_ingress\_policies) | Ingress policies for the perimeter | <pre>list(object({<br/>    identity_type = optional(string)<br/>    identities    = optional(list(string))<br/>    sources = optional(list(object({<br/>      access_level = optional(string)<br/>      resource     = optional(string)<br/>    })))<br/>    resources = optional(list(string))<br/>    operations = optional(list(object({<br/>      service_name = string<br/>      method_selectors = optional(list(object({<br/>        method     = optional(string)<br/>        permission = optional(string)<br/>      })))<br/>    })))<br/>  }))</pre> | `[]` | no |
| <a name="input_perimeter_type"></a> [perimeter\_type](#input\_perimeter\_type) | Type of service perimeter: PERIMETER\_TYPE\_REGULAR or PERIMETER\_TYPE\_BRIDGE | `string` | `"PERIMETER_TYPE_REGULAR"` | no |
| <a name="input_protected_projects"></a> [protected\_projects](#input\_protected\_projects) | List of project numbers to protect within the perimeter | `list(string)` | `[]` | no |
| <a name="input_restricted_services"></a> [restricted\_services](#input\_restricted\_services) | List of GCP services to restrict (e.g., ['storage.googleapis.com', 'bigquery.googleapis.com']) | `list(string)` | `[]` | no |
| <a name="input_vpc_accessible_services"></a> [vpc\_accessible\_services](#input\_vpc\_accessible\_services) | Configuration for VPC accessible services | <pre>object({<br/>    enable_restriction = bool<br/>    allowed_services   = list(string)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_levels"></a> [access\_levels](#output\_access\_levels) | Map of created access levels |
| <a name="output_access_policy"></a> [access\_policy](#output\_access\_policy) | The created access policy resource (if created) |
| <a name="output_access_policy_name"></a> [access\_policy\_name](#output\_access\_policy\_name) | The name of the access policy |
| <a name="output_id"></a> [id](#output\_id) | The ID of the service perimeter |
| <a name="output_name"></a> [name](#output\_name) | The resource name of the service perimeter |
| <a name="output_perimeter"></a> [perimeter](#output\_perimeter) | The service perimeter resource |
| <a name="output_protected_project_numbers"></a> [protected\_project\_numbers](#output\_protected\_project\_numbers) | List of project numbers protected by this perimeter |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the service perimeter |
<!-- END_TF_DOCS -->