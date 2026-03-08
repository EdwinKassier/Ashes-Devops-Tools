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

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	account_id = 
	display_name = 
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
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_folder_iam_member.sa_folder_roles (modules/iam/service_account/main.tf#L22)
- resource.google_organization_iam_member.sa_org_roles (modules/iam/service_account/main.tf#L31)
- resource.google_project_iam_member.sa_project_roles (modules/iam/service_account/main.tf#L13)
- resource.google_service_account.service_account (modules/iam/service_account/main.tf#L5)
- resource.google_service_account_iam_member.impersonation (modules/iam/service_account/main.tf#L41)
- resource.google_service_account_iam_member.workload_identity_user (modules/iam/service_account/main.tf#L50)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | The service account ID (the part before @project.iam.gserviceaccount.com) | `string` | n/a | yes |
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | The display name for the service account | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the service account will be created | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | A description of the service account | `string` | `""` | no |
| <a name="input_folder_roles"></a> [folder\_roles](#input\_folder\_roles) | List of folder-level IAM role assignments | <pre>list(object({<br/>    folder_id = string<br/>    role      = string<br/>  }))</pre> | `[]` | no |
| <a name="input_impersonation_members"></a> [impersonation\_members](#input\_impersonation\_members) | List of members allowed to impersonate this service account (format: user:email, group:email, serviceAccount:email) | `list(string)` | `[]` | no |
| <a name="input_organization_roles"></a> [organization\_roles](#input\_organization\_roles) | List of organization-level IAM role assignments | <pre>list(object({<br/>    org_id = string<br/>    role   = string<br/>  }))</pre> | `[]` | no |
| <a name="input_project_roles"></a> [project\_roles](#input\_project\_roles) | List of IAM roles to grant to the service account at project level | `list(string)` | `[]` | no |
| <a name="input_workload_identity_members"></a> [workload\_identity\_members](#input\_workload\_identity\_members) | List of members allowed to use this service account via Workload Identity (format: principalSet://... or serviceAccount:...) | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_email"></a> [email](#output\_email) | The email address of the service account |
| <a name="output_impersonation_members"></a> [impersonation\_members](#output\_impersonation\_members) | List of members allowed to impersonate this service account |
| <a name="output_member"></a> [member](#output\_member) | The service account member string for use in IAM policies |
| <a name="output_name"></a> [name](#output\_name) | The fully-qualified name of the service account |
| <a name="output_project_roles"></a> [project\_roles](#output\_project\_roles) | List of project-level roles granted to the service account |
| <a name="output_unique_id"></a> [unique\_id](#output\_unique\_id) | The unique ID of the service account |
<!-- END_TF_DOCS -->