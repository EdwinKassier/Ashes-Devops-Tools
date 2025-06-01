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
  source = "./modules/iam/organisation"

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
| org_admin_members | List of members to have organization admin role | list(string) | [] | no |
| billing_admin_members | List of members to have billing admin role | list(string) | [] | no |
| allowed_regions | List of allowed GCP regions for resource creation | list(string) | ["europe-west1", "europe-west2", "us-central1"] | no |
| tags | Tags to be applied to all resources | map(string) | {} | no |

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