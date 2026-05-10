# Supabase Settings Module

Manages auth and API configuration for an existing Supabase project via `supabase_settings`.

## ⚠️ Important

Destroying this resource is a **no-op** — the Supabase Management API provides no "reset to defaults" endpoint. Remove the Terraform resource to stop managing settings, but the existing values remain in Supabase.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_ref = 
	
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


- resource.supabase_settings.this (modules/supabase/settings/main.tf#L10)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_ref"></a> [project\_ref](#input\_project\_ref) | The Supabase project ref — the `id` output from modules/supabase/project. Must be a 20-character lowercase alphanumeric string. | `string` | n/a | yes |
| <a name="input_api_max_rows"></a> [api\_max\_rows](#input\_api\_max\_rows) | Maximum rows returned by a single REST API request (100–100 000). | `number` | `1000` | no |
| <a name="input_db_extra_search_path"></a> [db\_extra\_search\_path](#input\_db\_extra\_search\_path) | Comma-separated list of schemas appended to the Postgres search\_path. | `string` | `"public,extensions"` | no |
| <a name="input_db_schema"></a> [db\_schema](#input\_db\_schema) | Comma-separated list of Postgres schemas exposed via the REST API. | `string` | `"public,graphql_public"` | no |
| <a name="input_disable_signup"></a> [disable\_signup](#input\_disable\_signup) | Disable new user sign-ups. Set true for production environments to prevent unwanted registrations. | `bool` | `false` | no |
| <a name="input_jwt_expiry"></a> [jwt\_expiry](#input\_jwt\_expiry) | JWT access token expiry in seconds (300–604 800, i.e. 5 minutes to 7 days). | `number` | `3600` | no |
| <a name="input_mailer_autoconfirm"></a> [mailer\_autoconfirm](#input\_mailer\_autoconfirm) | Auto-confirm email addresses on signup without sending a confirmation email. Safe for QA; disable for production. | `bool` | `false` | no |
| <a name="input_password_min_length"></a> [password\_min\_length](#input\_password\_min\_length) | Minimum password length for user accounts (6–100). Default 12 matches the collects reference implementation. | `number` | `12` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_project_ref"></a> [project\_ref](#output\_project\_ref) | The Supabase project ref this settings resource manages. |
| <a name="output_settings_id"></a> [settings\_id](#output\_settings\_id) | The Terraform resource ID of the supabase\_settings resource. |
<!-- END_TF_DOCS -->
