# Principal Access Boundary

Creates an organization-level [principal access boundary](https://cloud.google.com/iam/docs/principal-access-boundary-policies) (PAB) policy and binds it to the service accounts of one or more projects. Bound principals can use their permissions only on the listed resources (default: this organization), whatever their allow policies grant, so a stolen automation token cannot act on resources in another organization.

Used by `modules/gcp/stages/organization` (`enable_principal_access_boundary`, default off) for the landing-zone automation project. Validate on a non-production organization first: a boundary that omits a resource the automation needs makes those calls fail with permission denied.

## Usage

```hcl
module "automation_boundary" {
  source = "../../iam/principal-access-boundary"

  organization_id  = "123456789012"
  project_bindings = { admin = "acme-admin-1a2b3c4d" }
}
```

The applying identity needs `roles/iam.principalAccessBoundaryAdmin` at the organization and `resourcemanager.projects.createPolicyBinding` (for example `roles/resourcemanager.projectIamAdmin`) on each bound project.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	organization_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |



## Resources

The following resources are created:


- resource.google_iam_principal_access_boundary_policy.this (modules/gcp/iam/principal-access-boundary/main.tf#L17)
- resource.google_iam_projects_policy_binding.this (modules/gcp/iam/principal-access-boundary/main.tf#L36)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Numeric organization ID that owns the principal access boundary policy. | `string` | n/a | yes |
| <a name="input_allowed_resources"></a> [allowed\_resources](#input\_allowed\_resources) | Resource-hierarchy nodes the bound principals may act on (//cloudresourcemanager.googleapis.com/organizations/<id>, .../folders/<id> or .../projects/<id>). Empty = this organization only. | `list(string)` | `[]` | no |
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | Display name of the policy (at most 63 characters). | `string` | `"Landing zone automation boundary"` | no |
| <a name="input_enforcement_version"></a> [enforcement\_version](#input\_enforcement\_version) | Enforcement version: which permissions IAM enforces the boundary for. A pinned number keeps behaviour stable when Google adds coverage; "latest" follows it automatically. | `string` | `"1"` | no |
| <a name="input_policy_id"></a> [policy\_id](#input\_policy\_id) | ID of the principal access boundary policy (also the prefix of every binding ID). | `string` | `"automation-boundary"` | no |
| <a name="input_project_bindings"></a> [project\_bindings](#input\_project\_bindings) | Map of short binding key => project ID. Every service account in each project is bound to the boundary (principal set //cloudresourcemanager.googleapis.com/projects/<id>). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_binding_ids"></a> [binding\_ids](#output\_binding\_ids) | Map of binding key => policy binding ID. |
| <a name="output_bound_principal_sets"></a> [bound\_principal\_sets](#output\_bound\_principal\_sets) | Map of binding key => principal set bound to the boundary. |
| <a name="output_boundary_resources"></a> [boundary\_resources](#output\_boundary\_resources) | Resources the bound principals may act on. |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | ID of the principal access boundary policy. |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | Full resource name of the principal access boundary policy. |
<!-- END_TF_DOCS -->
