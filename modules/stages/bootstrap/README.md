# Bootstrap Module

The foundation of the entire landing zone. This module bootstraps the initial administrative validation and automation capabilities.

## Purpose

- Creates the `admin` project (the seed project)
- Enables core APIs required for Terraform to operate
- Creates the Terraform Admin Service Account
- Sets up Workload Identity Federation for GitHub Actions
- Configures storage for Terraform state

## Usage

```hcl
module "bootstrap" {
  source = "../../modules/stages/bootstrap"

  org_id          = "123456789"
  billing_account = "000000-000000-000000"
  project_prefix  = "my-org"
  
  github_org  = "MyOrg"
  github_repo = "infra-repo"
  
  # Admin email for impersonation
  admin_email = "admin@example.com"
}
```

## Security

This module grants highly privileged roles (`roles/resourcemanager.organizationViewer`, `roles/logging.admin`, etc.) to the created Service Account. 
- **WIF Branch Restrictions**: Configured to only allow `main` branch for production operations.
- **Impersonation**: Principals must impersonate the SA, no keys are generated.

## Outputs

- `admin_project_id`: The ID of the created admin project
- `terraform_sa_email`: The email of the automation service account
- `workload_identity_provider`: The ID of the WIF provider
