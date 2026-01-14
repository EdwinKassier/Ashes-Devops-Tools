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
