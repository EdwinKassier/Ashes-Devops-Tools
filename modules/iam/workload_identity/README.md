# Google Cloud Workload Identity Federation Module

This Terraform module sets up Workload Identity Federation for keyless authentication from external identity providers like GitHub Actions, GitLab CI, and AWS.

## Why Workload Identity?

> [!IMPORTANT]
> **Avoid service account keys!** They are long-lived credentials that pose significant security risks if leaked. Workload Identity Federation uses short-lived, automatically rotated tokens.

### Benefits

- No service account keys to manage or rotate
- Short-lived tokens (1 hour by default)
- Audit trail of external identity usage
- Fine-grained access control based on attributes
- Support for multiple identity providers

## Usage

### GitHub Actions

```hcl
module "github_workload_identity" {
  source = "./modules/iam/workload_identity"

  project_id   = "my-project"
  pool_id      = "github-pool"
  display_name = "GitHub Actions Pool"

  enable_github_provider = true
  github_organization    = "my-org"  # Optional: restrict to org

  # Bind specific repos to service accounts
  github_sa_bindings = [
    {
      repository            = "my-org/my-repo"
      service_account_email = "github-deployer@my-project.iam.gserviceaccount.com"
    }
  ]
}
```

**GitHub Actions Workflow:**

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ module.github_workload_identity.github_workload_identity_provider }}
          service_account: github-deployer@my-project.iam.gserviceaccount.com
```

### GitLab CI

```hcl
module "gitlab_workload_identity" {
  source = "./modules/iam/workload_identity"

  project_id   = "my-project"
  pool_id      = "gitlab-pool"
  display_name = "GitLab CI Pool"

  enable_gitlab_provider = true
  gitlab_url             = "https://gitlab.com"
  gitlab_namespace       = "my-group"  # Optional: restrict to group

  gitlab_sa_bindings = [
    {
      project_path          = "my-group/my-project"
      service_account_email = "gitlab-deployer@my-project.iam.gserviceaccount.com"
    }
  ]
}
```

### Cross-Cloud (AWS)

```hcl
module "aws_workload_identity" {
  source = "./modules/iam/workload_identity"

  project_id   = "my-project"
  pool_id      = "aws-pool"
  display_name = "AWS Cross-Cloud Pool"

  enable_aws_provider = true
  aws_account_id      = "123456789012"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | GCP project ID | string | - | yes |
| pool_id | Workload Identity Pool ID | string | - | yes |
| display_name | Display name for the pool | string | - | yes |
| description | Pool description | string | "Workload Identity Pool..." | no |
| disabled | Whether pool is disabled | bool | false | no |
| enable_github_provider | Enable GitHub Actions OIDC | bool | false | no |
| github_organization | Restrict to GitHub org | string | null | no |
| github_sa_bindings | Repo to SA bindings | list(object) | [] | no |
| enable_gitlab_provider | Enable GitLab CI OIDC | bool | false | no |
| gitlab_url | GitLab instance URL | string | "https://gitlab.com" | no |
| gitlab_namespace | Restrict to GitLab namespace | string | null | no |
| gitlab_sa_bindings | Project to SA bindings | list(object) | [] | no |
| enable_aws_provider | Enable AWS OIDC | bool | false | no |
| aws_account_id | AWS account to allow | string | null | no |

## Outputs

| Name | Description |
|------|-------------|
| pool_id | Workload Identity Pool ID |
| pool_name | Fully-qualified pool name |
| github_provider_name | GitHub provider name |
| gitlab_provider_name | GitLab provider name |
| aws_provider_name | AWS provider name |
| github_workload_identity_provider | Provider string for GitHub Actions |
| github_principal_set_prefix | Prefix for principal sets |

## Security Considerations

1. **Restrict by organization/account**: Always set `github_organization`, `gitlab_namespace`, or `aws_account_id` to prevent unauthorized access
2. **Least privilege**: Only grant necessary roles to service accounts
3. **Audit logs**: Enable Cloud Audit Logs to monitor workload identity usage
4. **Review bindings**: Regularly review which repositories have access to which service accounts

## Related Modules

- `service_account` - Create service accounts for workload identity to impersonate
- `role` - Create custom roles with minimal permissions

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	display_name = 
	pool_id = 
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
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_iam_workload_identity_pool.pool (modules/iam/workload_identity/main.tf#L5)
- resource.google_iam_workload_identity_pool_provider.aws (modules/iam/workload_identity/main.tf#L88)
- resource.google_iam_workload_identity_pool_provider.github (modules/iam/workload_identity/main.tf#L14)
- resource.google_iam_workload_identity_pool_provider.gitlab (modules/iam/workload_identity/main.tf#L63)
- resource.google_iam_workload_identity_pool_provider.tfc (modules/iam/workload_identity/main.tf#L129)
- resource.google_service_account_iam_member.github_workload_identity (modules/iam/workload_identity/main.tf#L111)
- resource.google_service_account_iam_member.gitlab_workload_identity (modules/iam/workload_identity/main.tf#L120)
- resource.google_service_account_iam_member.tfc_workload_identity (modules/iam/workload_identity/main.tf#L160)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | Display name for the Workload Identity Pool | `string` | n/a | yes |
| <a name="input_pool_id"></a> [pool\_id](#input\_pool\_id) | The ID for the Workload Identity Pool | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Workload Identity Pool will be created | `string` | n/a | yes |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID to restrict access to | `string` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the Workload Identity Pool | `string` | `"Workload Identity Pool for external authentication"` | no |
| <a name="input_disabled"></a> [disabled](#input\_disabled) | Whether the pool is disabled | `bool` | `false` | no |
| <a name="input_enable_aws_provider"></a> [enable\_aws\_provider](#input\_enable\_aws\_provider) | Enable AWS OIDC provider for cross-cloud authentication | `bool` | `false` | no |
| <a name="input_enable_github_provider"></a> [enable\_github\_provider](#input\_enable\_github\_provider) | Enable GitHub Actions OIDC provider | `bool` | `false` | no |
| <a name="input_enable_gitlab_provider"></a> [enable\_gitlab\_provider](#input\_enable\_gitlab\_provider) | Enable GitLab CI OIDC provider | `bool` | `false` | no |
| <a name="input_enable_tfc_provider"></a> [enable\_tfc\_provider](#input\_enable\_tfc\_provider) | Enable Terraform Cloud OIDC provider for Dynamic Credentials | `bool` | `false` | no |
| <a name="input_github_allowed_refs"></a> [github\_allowed\_refs](#input\_github\_allowed\_refs) | List of allowed git refs for GitHub Actions (e.g., ['refs/heads/main', 'refs/heads/release/*']). When set, only workflows triggered from these refs can authenticate. | `list(string)` | `[]` | no |
| <a name="input_github_attribute_condition_override"></a> [github\_attribute\_condition\_override](#input\_github\_attribute\_condition\_override) | Full custom attribute condition for GitHub provider. When set, overrides the default condition based on organization and allowed\_refs. | `string` | `null` | no |
| <a name="input_github_organization"></a> [github\_organization](#input\_github\_organization) | GitHub organization to restrict access to (optional) | `string` | `null` | no |
| <a name="input_github_sa_bindings"></a> [github\_sa\_bindings](#input\_github\_sa\_bindings) | List of GitHub repository to service account bindings | <pre>list(object({<br/>    repository            = string # Format: owner/repo<br/>    service_account_email = string<br/>  }))</pre> | `[]` | no |
| <a name="input_gitlab_namespace"></a> [gitlab\_namespace](#input\_gitlab\_namespace) | GitLab namespace to restrict access to (optional) | `string` | `null` | no |
| <a name="input_gitlab_sa_bindings"></a> [gitlab\_sa\_bindings](#input\_gitlab\_sa\_bindings) | List of GitLab project to service account bindings | <pre>list(object({<br/>    project_path          = string # Format: group/project<br/>    service_account_email = string<br/>  }))</pre> | `[]` | no |
| <a name="input_gitlab_url"></a> [gitlab\_url](#input\_gitlab\_url) | GitLab instance URL (e.g., https://gitlab.com) | `string` | `"https://gitlab.com"` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization name | `string` | `null` | no |
| <a name="input_tfc_sa_bindings"></a> [tfc\_sa\_bindings](#input\_tfc\_sa\_bindings) | List of TFC workspace to service account bindings | <pre>list(object({<br/>    workspace_name        = string<br/>    project_name          = optional(string, "*")<br/>    service_account_email = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_provider_name"></a> [aws\_provider\_name](#output\_aws\_provider\_name) | The fully-qualified name of the AWS provider |
| <a name="output_github_principal_set_prefix"></a> [github\_principal\_set\_prefix](#output\_github\_principal\_set\_prefix) | Prefix for GitHub principal set (append /attribute.repository/owner/repo) |
| <a name="output_github_provider_name"></a> [github\_provider\_name](#output\_github\_provider\_name) | The fully-qualified name of the GitHub OIDC provider |
| <a name="output_github_workload_identity_provider"></a> [github\_workload\_identity\_provider](#output\_github\_workload\_identity\_provider) | Provider string for use in GitHub Actions workflow (google-github-actions/auth) |
| <a name="output_gitlab_provider_name"></a> [gitlab\_provider\_name](#output\_gitlab\_provider\_name) | The fully-qualified name of the GitLab OIDC provider |
| <a name="output_pool_id"></a> [pool\_id](#output\_pool\_id) | The Workload Identity Pool ID |
| <a name="output_pool_name"></a> [pool\_name](#output\_pool\_name) | The fully-qualified name of the Workload Identity Pool |
<!-- END_TF_DOCS -->