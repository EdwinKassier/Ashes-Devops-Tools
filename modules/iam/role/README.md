# Google Cloud Custom IAM Role Module

This Terraform module creates custom IAM roles at either the project or organization level.

## Why Custom Roles?

Custom roles allow you to implement the **Principle of Least Privilege** by granting only the specific permissions needed for a task, rather than using overly broad predefined roles.

## Usage

### Project-Level Custom Role

```hcl
module "storage_reader_role" {
  source = "./modules/iam/role"

  level       = "project"
  project_id  = "my-project"
  role_id     = "storageObjectReader"
  title       = "Storage Object Reader"
  description = "Read-only access to Cloud Storage objects"

  permissions = [
    "storage.objects.get",
    "storage.objects.list"
  ]
}
```

### Organization-Level Custom Role

```hcl
module "org_security_viewer" {
  source = "./modules/iam/role"

  level       = "organization"
  org_id      = "123456789"
  role_id     = "securityCenterViewer"
  title       = "Security Center Viewer"
  description = "Read-only access to Security Command Center findings"

  permissions = [
    "securitycenter.findings.list",
    "securitycenter.findings.get",
    "securitycenter.sources.list"
  ]
}
```

### Using with Service Account Module

```hcl
module "custom_role" {
  source = "./modules/iam/role"

  level       = "project"
  project_id  = "my-project"
  role_id     = "customDeployer"
  title       = "Custom Deployer"

  permissions = [
    "run.services.create",
    "run.services.update",
    "run.services.delete"
  ]
}

module "deployer_sa" {
  source = "./modules/iam/service_account"

  project_id   = "my-project"
  account_id   = "deployer"
  display_name = "Deployer Service Account"

  project_roles = [
    module.custom_role.name  # Use the custom role
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| level | Level: 'project' or 'organization' | string | "project" | no |
| project_id | Project ID (required when level='project') | string | null | conditional |
| org_id | Organization ID (required when level='organization') | string | null | conditional |
| role_id | The camelCaseRoleId (3-64 chars) | string | - | yes |
| title | Human-readable title | string | - | yes |
| description | Role description | string | "" | no |
| permissions | List of permissions to grant | list(string) | - | yes |
| stage | Launch stage (GA, BETA, ALPHA, etc.) | string | "GA" | no |

## Outputs

| Name | Description |
|------|-------------|
| role_id | The ID of the created custom role |
| name | The resource name (for use in IAM bindings) |
| title | The human-readable title |
| stage | The launch stage |
| permissions | List of permissions granted |
| level | The level (project or organization) |

## Finding Permissions

To find the permissions you need:

1. **GCP Console**: IAM & Admin > Roles > Select a predefined role > View permissions
2. **gcloud CLI**: `gcloud iam roles describe roles/storage.admin`
3. **Documentation**: [GCP IAM Permissions Reference](https://cloud.google.com/iam/docs/permissions-reference)

## Best Practices

1. **Start minimal**: Begin with the fewest permissions possible, add more as needed
2. **Use predefined roles first**: Only create custom roles when predefined roles are too broad
3. **Document purpose**: Always include a meaningful description
4. **Version control**: Track permission changes in your Terraform code
5. **Review regularly**: Audit custom roles for unused permissions

## Related Modules

- `service_account` - Create service accounts to grant custom roles to
- `identity_group` - Manage groups to grant custom roles to
