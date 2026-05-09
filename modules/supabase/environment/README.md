# Supabase Environment Module

Composite module that creates a complete Supabase environment: a project, auth and API settings, and exposes the project's API keys.

This is the primary building block for per-environment deployments. Use one instance per environment (QA, UAT, production).

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

## Modules


- project - ../project
- settings - ../settings


## Resources

The following resources are created:


- data source.supabase_apikeys.this (modules/supabase/environment/main.tf#L39)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_database_password"></a> [database\_password](#input\_database\_password) | Initial Postgres database password. Minimum 16 characters.<br/>Ignored after initial project creation — see modules/supabase/project for details. | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Supabase organisation ID. Find this in the Supabase dashboard under<br/>Organisation Settings → General → Organisation ID.<br/>Format: lowercase alphanumeric, at least 8 characters. | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Display name for the Supabase project (3–64 characters). | `string` | n/a | yes |
| <a name="input_api_max_rows"></a> [api\_max\_rows](#input\_api\_max\_rows) | Maximum rows returned by a single REST API request (100–100 000). | `number` | `1000` | no |
| <a name="input_db_extra_search_path"></a> [db\_extra\_search\_path](#input\_db\_extra\_search\_path) | Comma-separated list of schemas appended to the Postgres search\_path. | `string` | `"public,extensions"` | no |
| <a name="input_db_schema"></a> [db\_schema](#input\_db\_schema) | Comma-separated list of Postgres schemas exposed via the REST API. | `string` | `"public,graphql_public"` | no |
| <a name="input_disable_signup"></a> [disable\_signup](#input\_disable\_signup) | Disable new user sign-ups. Set true for production environments. | `bool` | `false` | no |
| <a name="input_jwt_expiry"></a> [jwt\_expiry](#input\_jwt\_expiry) | JWT access token expiry in seconds (300–604 800). | `number` | `3600` | no |
| <a name="input_mailer_autoconfirm"></a> [mailer\_autoconfirm](#input\_mailer\_autoconfirm) | Auto-confirm email addresses on signup without sending a confirmation email. QA only; disable in production. | `bool` | `false` | no |
| <a name="input_password_min_length"></a> [password\_min\_length](#input\_password\_min\_length) | Minimum password length for user accounts (6–100). Default 12 matches the collects reference implementation. | `number` | `12` | no |
| <a name="input_region"></a> [region](#input\_region) | Supabase deployment region slug (e.g. 'eu-west-2'). See https://supabase.com/docs/guides/platform/regions. | `string` | `"eu-west-2"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_anon_key"></a> [anon\_key](#output\_anon\_key) | The Supabase anon key (public credential). Intentionally NOT marked sensitive<br/>because anon\_key is a public key safe to embed in client-side code, and<br/>marking it sensitive causes Terraform to refuse its use in for-expression<br/>filter conditions — a pattern callers need when wiring multi-environment<br/>Vercel env vars. The service\_role\_key IS sensitive. |
| <a name="output_api_url"></a> [api\_url](#output\_api\_url) | The Supabase project REST API URL (https://<project\_ref>.supabase.co). |
| <a name="output_database_password"></a> [database\_password](#output\_database\_password) | The initial database password set at project creation. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The Supabase project ref (20-char alphanumeric). |
| <a name="output_project_name"></a> [project\_name](#output\_project\_name) | The Supabase project display name. |
| <a name="output_service_role_key"></a> [service\_role\_key](#output\_service\_role\_key) | The Supabase service role key. Treat as a secret — grants full database access bypassing Row Level Security. |
<!-- END_TF_DOCS -->
