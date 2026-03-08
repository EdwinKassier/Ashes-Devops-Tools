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

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	permissions = 
	role_id = 
	title = 
	
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


- resource.google_organization_iam_custom_role.org_role (modules/iam/role/main.tf#L17)
- resource.google_project_iam_custom_role.project_role (modules/iam/role/main.tf#L5)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_permissions"></a> [permissions](#input\_permissions) | The list of permissions that the custom role will grant | `list(string)` | n/a | yes |
| <a name="input_role_id"></a> [role\_id](#input\_role\_id) | The camelCaseRoleId for the custom role (e.g., 'myCustomRole') | `string` | n/a | yes |
| <a name="input_title"></a> [title](#input\_title) | A human-readable title for the custom role | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | A description of the custom role | `string` | `""` | no |
| <a name="input_level"></a> [level](#input\_level) | Level at which to create the custom role: 'project' or 'organization' | `string` | `"project"` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The organization ID where the custom role will be created (required when level is 'organization') | `string` | `null` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the custom role will be created (required when level is 'project') | `string` | `null` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | The current launch stage of the role (ALPHA, BETA, GA, DEPRECATED, DISABLED, EAP) | `string` | `"GA"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_level"></a> [level](#output\_level) | The level at which the role was created (project or organization) |
| <a name="output_name"></a> [name](#output\_name) | The resource name of the created custom role |
| <a name="output_permissions"></a> [permissions](#output\_permissions) | The list of permissions granted by this role |
| <a name="output_role_id"></a> [role\_id](#output\_role\_id) | The ID of the created custom role |
| <a name="output_stage"></a> [stage](#output\_stage) | The current launch stage of the role |
| <a name="output_title"></a> [title](#output\_title) | The human-readable title of the custom role |
<!-- END_TF_DOCS -->