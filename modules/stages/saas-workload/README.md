# SaaS Workload Stage Module

Provisions a complete SaaS environment by composing three child modules:
`supabase/environment`, `supabase/vault-secrets` (optional), and `vercel/project` (optional).

## Deployment Phases

Apply in three phases to avoid dependency ordering issues:

1. **Phase 1** — `enable_vercel = false`, `enable_vault_secrets = false`. Supabase project is created. Note the `supabase_project_id` output.
2. **Phase 2** — `enable_vault_secrets = true`. Supply `postgres_url` (session-mode pooler from dashboard) and `supabase_ssl_cert`.
3. **Phase 3** — `enable_vercel = true`. Supply Vercel `team_id`, `github_repo`, and all env var maps.

## Provider Configuration Requirement

This module declares `supabase`, `vercel`, and `null` providers in `versions.tf`. **All three must be configured in the calling root** even when `enable_vercel = false` or `enable_vault_secrets = false`. This is a Terraform constraint: `required_providers` is evaluated at init time regardless of `count` values.

- The `null` provider requires no credentials (add `provider "null" {}` to the root).
- The `vercel` provider requires `VERCEL_API_TOKEN` even when `enable_vercel = false`.
- The `supabase` provider requires `SUPABASE_ACCESS_TOKEN`.

**Supabase-only deployments:** Call `modules/supabase/environment` directly to avoid the Vercel provider requirement entirely.

## Node.js Requirement

`enable_vault_secrets = true` requires **Node.js >= 18** in the execution environment and the `pg` package installed in `modules/supabase/vault-secrets/scripts/`. Run `npm install` in that directory before applying.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	supabase_database_password = 
	supabase_organization_id = 
	supabase_project_name = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |
| <a name="requirement_supabase"></a> [supabase](#requirement\_supabase) | ~> 1.0 |
| <a name="requirement_vercel"></a> [vercel](#requirement\_vercel) | ~> 4.0 |



## Modules


- supabase_environment - ../../supabase/environment
- vault_secrets - ../../supabase/vault-secrets
- vercel_project - ../../vercel/project




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_supabase_database_password"></a> [supabase\_database\_password](#input\_supabase\_database\_password) | Initial Postgres database password. Minimum 16 characters. Ignored after initial creation. | `string` | n/a | yes |
| <a name="input_supabase_organization_id"></a> [supabase\_organization\_id](#input\_supabase\_organization\_id) | Supabase organisation ID (from dashboard.supabase.com → Organisation Settings). Lowercase alphanumeric, at least 8 characters. | `string` | n/a | yes |
| <a name="input_supabase_project_name"></a> [supabase\_project\_name](#input\_supabase\_project\_name) | Display name for the Supabase project (3–64 characters). | `string` | n/a | yes |
| <a name="input_enable_vault_secrets"></a> [enable\_vault\_secrets](#input\_enable\_vault\_secrets) | When true, bootstrap and reconcile the Supabase Vault. Requires Node.js >= 18 in the execution environment and var.postgres\_url. | `bool` | `false` | no |
| <a name="input_enable_vercel"></a> [enable\_vercel](#input\_enable\_vercel) | When true, create and configure the Vercel project. Requires var.vercel\_team\_id and var.vercel\_github\_repo. | `bool` | `false` | no |
| <a name="input_postgres_url"></a> [postgres\_url](#input\_postgres\_url) | Session-mode pooler URL (port 5432) for vault bootstrap and reconcile.<br/>Required when enable\_vault\_secrets = true. Leave empty when disabled.<br/>Format: postgresql://postgres.<project\_ref>:<password>@<host>:5432/postgres | `string` | `""` | no |
| <a name="input_supabase_api_max_rows"></a> [supabase\_api\_max\_rows](#input\_supabase\_api\_max\_rows) | Maximum rows returned by a single REST API request (100–100 000). | `number` | `1000` | no |
| <a name="input_supabase_db_extra_search_path"></a> [supabase\_db\_extra\_search\_path](#input\_supabase\_db\_extra\_search\_path) | Comma-separated list of schemas appended to the Postgres search\_path. | `string` | `"public,extensions"` | no |
| <a name="input_supabase_db_schema"></a> [supabase\_db\_schema](#input\_supabase\_db\_schema) | Comma-separated list of Postgres schemas exposed via the REST API. | `string` | `"public,graphql_public"` | no |
| <a name="input_supabase_disable_signup"></a> [supabase\_disable\_signup](#input\_supabase\_disable\_signup) | Disable new user sign-ups. Recommended true for production. | `bool` | `false` | no |
| <a name="input_supabase_jwt_expiry"></a> [supabase\_jwt\_expiry](#input\_supabase\_jwt\_expiry) | JWT access token expiry in seconds (300–604 800). | `number` | `3600` | no |
| <a name="input_supabase_mailer_autoconfirm"></a> [supabase\_mailer\_autoconfirm](#input\_supabase\_mailer\_autoconfirm) | Auto-confirm email addresses. QA only; disable for production. | `bool` | `false` | no |
| <a name="input_supabase_password_min_length"></a> [supabase\_password\_min\_length](#input\_supabase\_password\_min\_length) | Minimum password length for user accounts (6–100). Default 12 matches the collects reference implementation. | `number` | `12` | no |
| <a name="input_supabase_region"></a> [supabase\_region](#input\_supabase\_region) | Supabase deployment region slug (e.g. 'eu-west-2'). | `string` | `"eu-west-2"` | no |
| <a name="input_supabase_ssl_cert"></a> [supabase\_ssl\_cert](#input\_supabase\_ssl\_cert) | Base64-encoded Supabase CA certificate bundle. Required for pooler connections when enable\_vault\_secrets = true. | `string` | `""` | no |
| <a name="input_vault_secrets"></a> [vault\_secrets](#input\_vault\_secrets) | Desired vault state as name → value map. Only used when enable\_vault\_secrets = true. Names must be UPPER\_SNAKE\_CASE. | `map(string)` | `{}` | no |
| <a name="input_vercel_allowed_branches"></a> [vercel\_allowed\_branches](#input\_vercel\_allowed\_branches) | Git branches that trigger automatic Vercel builds. Builds on all other<br/>branches are skipped. Must contain at least one branch name.<br/>Only used when enable\_vercel = true. | `list(string)` | <pre>[<br/>  "main"<br/>]</pre> | no |
| <a name="input_vercel_domains"></a> [vercel\_domains](#input\_vercel\_domains) | Domain assignments for the Vercel project. environment must be one of: qa, uat, production. | <pre>list(object({<br/>    domain      = string<br/>    environment = string<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_framework"></a> [vercel\_framework](#input\_vercel\_framework) | Framework preset for the Vercel project (e.g. 'nextjs', 'remix', 'astro'). Set null for framework-agnostic projects. Only used when enable\_vercel = true. | `string` | `"nextjs"` | no |
| <a name="input_vercel_github_repo"></a> [vercel\_github\_repo](#input\_vercel\_github\_repo) | GitHub repository in 'org/repo' format. Required when enable\_vercel = true. | `string` | `""` | no |
| <a name="input_vercel_prod_env_vars"></a> [vercel\_prod\_env\_vars](#input\_vercel\_prod\_env\_vars) | Vercel environment variables for the production environment. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_production_branch"></a> [vercel\_production\_branch](#input\_vercel\_production\_branch) | Git branch for the Vercel production environment. Must be an existing branch. | `string` | `"main"` | no |
| <a name="input_vercel_project_name"></a> [vercel\_project\_name](#input\_vercel\_project\_name) | Vercel project name. Required when enable\_vercel = true. | `string` | `""` | no |
| <a name="input_vercel_qa_env_vars"></a> [vercel\_qa\_env\_vars](#input\_vercel\_qa\_env\_vars) | Vercel environment variables for the QA (preview) environment. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_root_directory"></a> [vercel\_root\_directory](#input\_vercel\_root\_directory) | Root directory within the repository for the Vercel project. Empty string means repository root. | `string` | `""` | no |
| <a name="input_vercel_serverless_region"></a> [vercel\_serverless\_region](#input\_vercel\_serverless\_region) | Vercel serverless function region code. | `string` | `"lhr1"` | no |
| <a name="input_vercel_shared_env_vars"></a> [vercel\_shared\_env\_vars](#input\_vercel\_shared\_env\_vars) | Vercel environment variables shared across all three environments. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_team_id"></a> [vercel\_team\_id](#input\_vercel\_team\_id) | Vercel team ID. Required when enable\_vercel = true. | `string` | `""` | no |
| <a name="input_vercel_uat_env_vars"></a> [vercel\_uat\_env\_vars](#input\_vercel\_uat\_env\_vars) | Vercel environment variables for the UAT custom environment. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_supabase_anon_key"></a> [supabase\_anon\_key](#output\_supabase\_anon\_key) | The Supabase anon key (public credential). Not marked sensitive by design — see supabase/environment module. |
| <a name="output_supabase_api_url"></a> [supabase\_api\_url](#output\_supabase\_api\_url) | The Supabase project REST API URL. |
| <a name="output_supabase_database_password"></a> [supabase\_database\_password](#output\_supabase\_database\_password) | The initial Supabase database password. |
| <a name="output_supabase_project_id"></a> [supabase\_project\_id](#output\_supabase\_project\_id) | The Supabase project ref. |
| <a name="output_supabase_service_role_key"></a> [supabase\_service\_role\_key](#output\_supabase\_service\_role\_key) | The Supabase service role key. Treat as a secret. |
| <a name="output_vault_managed_secret_names"></a> [vault\_managed\_secret\_names](#output\_vault\_managed\_secret\_names) | Names of vault secrets managed by this module. Null when enable\_vault\_secrets = false. |
| <a name="output_vercel_project_id"></a> [vercel\_project\_id](#output\_vercel\_project\_id) | The Vercel project ID. Null when enable\_vercel = false. |
| <a name="output_vercel_uat_environment_id"></a> [vercel\_uat\_environment\_id](#output\_vercel\_uat\_environment\_id) | The Vercel UAT custom environment ID. Null when enable\_vercel = false. |
<!-- END_TF_DOCS -->
