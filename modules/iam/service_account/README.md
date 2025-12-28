# Google Cloud Service Account Module

This Terraform module creates and manages Google Cloud service accounts with configurable IAM roles and impersonation settings.

## Security Best Practices

> [!IMPORTANT]
> This module intentionally does **NOT** create service account keys. Service account keys are a security risk and should be avoided. Use Workload Identity Federation instead.

### Authentication Alternatives

1. **Workload Identity Federation** - For external workloads (GitHub Actions, AWS, Azure)
2. **Service Account Impersonation** - For users/services that need temporary access
3. **Attached Service Account** - For GCP resources (Compute Engine, Cloud Run, etc.)

## Usage

### Basic Service Account

```hcl
module "my_service_account" {
  source = "./modules/iam/service_account"

  project_id   = "my-project"
  account_id   = "my-service-account"
  display_name = "My Service Account"
  description  = "Service account for application X"

  project_roles = [
    "roles/storage.objectViewer",
    "roles/pubsub.subscriber"
  ]
}
```

### Service Account with Impersonation

```hcl
module "terraform_sa" {
  source = "./modules/iam/service_account"

  project_id   = "my-project"
  account_id   = "terraform-deployer"
  display_name = "Terraform Deployer"
  description  = "Service account for Terraform deployments"

  project_roles = [
    "roles/compute.admin",
    "roles/storage.admin"
  ]

  # Allow specific users to impersonate this SA
  impersonation_members = [
    "user:admin@example.com",
    "group:platform-team@example.com"
  ]
}
```

### Service Account for Workload Identity (GitHub Actions)

```hcl
module "github_actions_sa" {
  source = "./modules/iam/service_account"

  project_id   = "my-project"
  account_id   = "github-actions"
  display_name = "GitHub Actions"
  description  = "Service account for GitHub Actions CI/CD"

  project_roles = [
    "roles/cloudbuild.builds.editor",
    "roles/storage.admin"
  ]

  # Allow GitHub Actions to use this SA via Workload Identity
  workload_identity_members = [
    "principalSet://iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/github/attribute.repository/my-org/my-repo"
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The ID of the project where the service account will be created | string | - | yes |
| account_id | The service account ID (6-30 chars, lowercase letters, numbers, hyphens) | string | - | yes |
| display_name | The display name for the service account | string | - | yes |
| description | A description of the service account | string | "" | no |
| project_roles | List of IAM roles to grant at project level | list(string) | [] | no |
| folder_roles | List of folder-level IAM role assignments | list(object) | [] | no |
| organization_roles | List of organization-level IAM role assignments | list(object) | [] | no |
| impersonation_members | Members allowed to impersonate this service account | list(string) | [] | no |
| workload_identity_members | Members allowed to use via Workload Identity | list(string) | [] | no |

## Outputs

| Name | Description |
|------|-------------|
| email | The email address of the service account |
| name | The fully-qualified name of the service account |
| unique_id | The unique ID of the service account |
| member | The service account member string for use in IAM policies |
| project_roles | List of project-level roles granted |

## Related Modules

- `workload_identity` - Set up Workload Identity Federation for external identities
- `role` - Create custom IAM roles
- `identity_group` - Manage Cloud Identity groups
