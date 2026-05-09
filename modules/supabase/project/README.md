# Supabase Project Module

Creates a single Supabase project via the `supabase/supabase` Terraform provider.

## ⚠️ Important

- `database_password` is set once at creation. Changes are ignored (the Management API does not support password rotation via Terraform).
- Destroying this resource **permanently deletes** the Supabase project and all data. Set `lifecycle.prevent_destroy = true` in production callers.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	database_password = 
	organization_id = 
	project_name = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_supabase"></a> [supabase](#requirement\_supabase) | ~> 1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_supabase"></a> [supabase](#provider\_supabase) | 1.9.0 |



## Resources

The following resources are created:


- resource.supabase_project.this (modules/supabase/project/main.tf#L13)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_database_password"></a> [database\_password](#input\_database\_password) | Initial Postgres database password. Minimum 16 characters.<br/>⚠️  After creation this value is IGNORED on subsequent applies —<br/>lifecycle.ignore\_changes is set because the Supabase Management API<br/>does not support rotating the password programmatically. Manage<br/>password rotation directly in the Supabase dashboard. | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Supabase organisation ID. Find this in the Supabase dashboard under<br/>Organisation Settings → General → Organisation ID.<br/>Format: lowercase alphanumeric, at least 8 characters. | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Display name for the Supabase project (3–64 characters). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Supabase deployment region slug. See<br/>https://supabase.com/docs/guides/platform/regions for the full list. | `string` | `"eu-west-2"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_database_password"></a> [database\_password](#output\_database\_password) | The database password as stored in Terraform state. This value is read from<br/>state, NOT re-fetched from the Supabase API (database\_password is write-only:<br/>the provider schema has computed=false, so no refresh occurs). The lifecycle<br/>block ignores changes to this attribute after creation, meaning if the password<br/>is rotated via the Supabase dashboard this output will silently return the<br/>original creation-time value. Treat as a bootstrap convenience only. |
| <a name="output_id"></a> [id](#output\_id) | The Supabase project ref — a 20-character lowercase alphanumeric string used as the project identifier in all API calls. |
| <a name="output_name"></a> [name](#output\_name) | The Supabase project display name. |
<!-- END_TF_DOCS -->
