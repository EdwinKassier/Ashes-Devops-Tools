# Bootstrap Module

The foundation of the entire landing zone. This module bootstraps the initial administrative validation and automation capabilities.

## Purpose

- Creates the `admin` project (the seed project)
- Enables core APIs required for Terraform to operate
- Creates the Terraform Admin Service Account
- Sets up Workload Identity Federation for GitHub Actions and Terraform Cloud
- Grants the central automation roles required by downstream stages

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
- `admin_project_number`: The numeric ID of the admin project
- `terraform_admin_email`: The email of the automation service account
- `suffix`: The shared random suffix used by downstream project naming

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	admin_email = 
	billing_account = 
	github_org = 
	github_repo = 
	org_id = 
	project_prefix = 
	tfc_workspaces = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

## Modules


- gh_oidc - ../../iam/workload_identity
- terraform_admin_sa - ../../iam/service_account
- tfc_oidc - ../../iam/workload_identity


## Resources

The following resources are created:


- resource.google_organization_iam_member.terraform_admin_exception_org_roles (modules/stages/bootstrap/main.tf#L123)
- resource.google_organization_iam_member.terraform_admin_standard_org_roles (modules/stages/bootstrap/main.tf#L108)
- resource.google_project.admin_project (modules/stages/bootstrap/main.tf#L2)
- resource.google_project_service.admin_project_services (modules/stages/bootstrap/main.tf#L20)
- resource.random_id.suffix (modules/stages/bootstrap/main.tf#L15)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | Email address for the organization administrator | `string` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing Account ID | `string` | n/a | yes |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub Organization | `string` | n/a | yes |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub Repository | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Organization ID | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix to use for project names | `string` | n/a | yes |
| <a name="input_tfc_workspaces"></a> [tfc\_workspaces](#input\_tfc\_workspaces) | List of TFC workspaces to grant access to Terraform Admin SA | `list(string)` | n/a | yes |
| <a name="input_enable_tfc_oidc"></a> [enable\_tfc\_oidc](#input\_enable\_tfc\_oidc) | Enable Terraform Cloud OIDC for Dynamic Credentials | `bool` | `true` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization name | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_project_id"></a> [admin\_project\_id](#output\_admin\_project\_id) | Project ID of the admin project |
| <a name="output_admin_project_number"></a> [admin\_project\_number](#output\_admin\_project\_number) | Project Number of the admin project |
| <a name="output_suffix"></a> [suffix](#output\_suffix) | Random suffix used for uniqueness |
| <a name="output_terraform_admin_email"></a> [terraform\_admin\_email](#output\_terraform\_admin\_email) | Email of the Terraform Admin Service Account |
<!-- END_TF_DOCS -->
