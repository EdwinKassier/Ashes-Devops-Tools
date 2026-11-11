# `envs/saas` (workspace `saas-<name>`)

Supabase and Vercel only. It declares no AWS or Google provider, so applying it needs no cloud credentials. Set `TF_WORKSPACE=saas-<name>`. `enable_supabase` and `enable_vercel` gate the two features independently. It can read the cloud roots' state to wire the secret bridge. Most inputs default to a key in `config/landing-zone.yaml`; an explicit variable (tfvars or an HCP Terraform workspace variable) wins over the config file. The description of each input names its config key. The config keys live under `saas.*`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |
| <a name="requirement_supabase"></a> [supabase](#requirement\_supabase) | ~> 1.0 |
| <a name="requirement_vercel"></a> [vercel](#requirement\_vercel) | >= 4.8.2, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bridge_rotation"></a> [bridge\_rotation](#input\_bridge\_rotation) | Rotation counter published as the non-sensitive bridge\_version output. A workload that bridges this workspace's Supabase secrets feeds it to its write-only *\_wo\_version, so bumping it (after rotating the database password or service-role key) re-pushes the bridged secret on the workload's next apply. Null = saas.bridge\_rotation from config/landing-zone.yaml, else 1. | `number` | `null` | no |
| <a name="input_cross_cloud_references"></a> [cross\_cloud\_references](#input\_cross\_cloud\_references) | Opt-in frontend-URL seam. Inject outputs from AWS/GCP workspaces into the<br/>Vercel app as shared environment variables, resolved from remote state at plan<br/>time (no AWS or GCP credentials needed, only tfc\_organization). Keyed by a<br/>label; each entry names the upstream workspace, the output to read, and the<br/>Vercel env var to set. Default empty: no cross-cloud reads, and this root stays<br/>standalone.<br/><br/>  workspace\_name  upstream TFC workspace, e.g. "gcp-workload-prod".<br/>  output\_key      the output to read from that workspace, e.g. "api\_endpoint".<br/>  vercel\_env\_key  the Vercel env var name to set, e.g. "NEXT\_PUBLIC\_API\_URL".<br/>  sensitive       mark the resulting Vercel env var sensitive (default true, write-only in Vercel; set false only for values that must be readable in the dashboard). | <pre>map(object({<br/>    workspace_name = string<br/>    output_key     = string<br/>    vercel_env_key = string<br/>    sensitive      = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_supabase"></a> [enable\_supabase](#input\_enable\_supabase) | Provision the Supabase project. Set false for a Vercel-only deployment — the Supabase inputs may then be left at their defaults. Null = saas.supabase from config/landing-zone.yaml, else true. | `bool` | `null` | no |
| <a name="input_enable_vault_secrets"></a> [enable\_vault\_secrets](#input\_enable\_vault\_secrets) | Bootstrap and reconcile the Supabase Vault. Requires Node.js >= 18 in the execution environment and var.postgres\_url. Default false. | `bool` | `false` | no |
| <a name="input_enable_vercel"></a> [enable\_vercel](#input\_enable\_vercel) | Provision the Vercel project. Set false for a Supabase-only deployment — the Vercel inputs may then be left at their defaults. Null = saas.vercel from config/landing-zone.yaml, else true. | `bool` | `null` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../config/landing-zone.yaml; "" disables the lookup. Read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_postgres_url"></a> [postgres\_url](#input\_postgres\_url) | Session-mode pooler URL (port 5432) for vault bootstrap. Required when enable\_vault\_secrets = true. | `string` | `""` | no |
| <a name="input_stack"></a> [stack](#input\_stack) | SaaS stack key in saas.stacks (config/landing-zone.yaml) this workspace deploys. Null = the workspace name without the saas- prefix (tfc-admin sets it explicitly on every saas-<name> workspace). | `string` | `null` | no |
| <a name="input_supabase_api_max_rows"></a> [supabase\_api\_max\_rows](#input\_supabase\_api\_max\_rows) | Maximum rows returned by a single REST API request (100–100 000). | `number` | `1000` | no |
| <a name="input_supabase_database_password"></a> [supabase\_database\_password](#input\_supabase\_database\_password) | Initial Postgres database password (min 16 chars). Required when enable\_supabase = true. Ignored after initial creation. | `string` | `""` | no |
| <a name="input_supabase_db_extra_search_path"></a> [supabase\_db\_extra\_search\_path](#input\_supabase\_db\_extra\_search\_path) | Comma-separated list of schemas appended to the Postgres search\_path. | `string` | `"public,extensions"` | no |
| <a name="input_supabase_db_schema"></a> [supabase\_db\_schema](#input\_supabase\_db\_schema) | Comma-separated list of Postgres schemas exposed via the REST API. | `string` | `"public,graphql_public"` | no |
| <a name="input_supabase_disable_signup"></a> [supabase\_disable\_signup](#input\_supabase\_disable\_signup) | Disable new user sign-ups. Recommended true for production. | `bool` | `false` | no |
| <a name="input_supabase_jwt_expiry"></a> [supabase\_jwt\_expiry](#input\_supabase\_jwt\_expiry) | JWT access token expiry in seconds (300–604 800). | `number` | `3600` | no |
| <a name="input_supabase_mailer_autoconfirm"></a> [supabase\_mailer\_autoconfirm](#input\_supabase\_mailer\_autoconfirm) | Auto-confirm email addresses. QA only; disable for production. | `bool` | `false` | no |
| <a name="input_supabase_organization_id"></a> [supabase\_organization\_id](#input\_supabase\_organization\_id) | Supabase organisation ID. Required when enable\_supabase = true; at least 8 lowercase alphanumeric characters. Empty = saas.stacks.<stack>.supabase.organization\_id, else saas.defaults.supabase.organization\_id, from config/landing-zone.yaml. | `string` | `""` | no |
| <a name="input_supabase_password_min_length"></a> [supabase\_password\_min\_length](#input\_supabase\_password\_min\_length) | Minimum password length for user accounts (6–100). | `number` | `12` | no |
| <a name="input_supabase_project_name"></a> [supabase\_project\_name](#input\_supabase\_project\_name) | Display name for the Supabase project (3–64 chars). Required when enable\_supabase = true. Empty = saas.stacks.<stack>.supabase.project\_name from config/landing-zone.yaml. | `string` | `""` | no |
| <a name="input_supabase_region"></a> [supabase\_region](#input\_supabase\_region) | Supabase deployment region slug (e.g. 'eu-west-2'). Null = saas.stacks.<stack>.supabase.region, else saas.defaults.supabase.region, else eu-west-2. | `string` | `null` | no |
| <a name="input_supabase_ssl_cert"></a> [supabase\_ssl\_cert](#input\_supabase\_ssl\_cert) | Base64-encoded Supabase CA certificate bundle for pooler connections. Used when enable\_vault\_secrets = true. | `string` | `""` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization name. Required only when cross\_cloud\_references is non-empty (it reads upstream workspace state). Leave null for a standalone SaaS deployment. Null = org.tfc.organization from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_vault_secrets"></a> [vault\_secrets](#input\_vault\_secrets) | Desired vault state as name → value map. Only used when enable\_vault\_secrets = true. Names must be UPPER\_SNAKE\_CASE. | `map(string)` | `{}` | no |
| <a name="input_vercel_allowed_branches"></a> [vercel\_allowed\_branches](#input\_vercel\_allowed\_branches) | Git branches that trigger automatic Vercel builds. Must contain at least one branch name. | `list(string)` | <pre>[<br/>  "main"<br/>]</pre> | no |
| <a name="input_vercel_domains"></a> [vercel\_domains](#input\_vercel\_domains) | Domain assignments for the Vercel project. environment must be one of: qa, uat, production. | <pre>list(object({<br/>    domain      = string<br/>    environment = string<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_framework"></a> [vercel\_framework](#input\_vercel\_framework) | Framework preset for the Vercel project (e.g. 'nextjs'). Set null for framework-agnostic projects. | `string` | `"nextjs"` | no |
| <a name="input_vercel_github_repo"></a> [vercel\_github\_repo](#input\_vercel\_github\_repo) | GitHub repository in 'org/repo' format. Required when enable\_vercel = true. Empty = saas.stacks.<stack>.vercel.github\_repo from config/landing-zone.yaml. | `string` | `""` | no |
| <a name="input_vercel_prod_env_vars"></a> [vercel\_prod\_env\_vars](#input\_vercel\_prod\_env\_vars) | Vercel environment variables for the production environment. Each entry's sensitive defaults to true (secure by default). | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, true)<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_production_branch"></a> [vercel\_production\_branch](#input\_vercel\_production\_branch) | Git branch for the Vercel production environment. Must be an existing branch. Null = saas.stacks.<stack>.vercel.production\_branch, else main. | `string` | `null` | no |
| <a name="input_vercel_project_name"></a> [vercel\_project\_name](#input\_vercel\_project\_name) | Vercel project name. Required when enable\_vercel = true. Empty = saas.stacks.<stack>.vercel.project\_name from config/landing-zone.yaml. | `string` | `""` | no |
| <a name="input_vercel_qa_env_vars"></a> [vercel\_qa\_env\_vars](#input\_vercel\_qa\_env\_vars) | Vercel environment variables for the QA (preview) environment. Each entry's sensitive defaults to true (secure by default). | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, true)<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_root_directory"></a> [vercel\_root\_directory](#input\_vercel\_root\_directory) | Root directory within the repository for the Vercel project. Empty string means repository root. | `string` | `""` | no |
| <a name="input_vercel_serverless_region"></a> [vercel\_serverless\_region](#input\_vercel\_serverless\_region) | Vercel serverless function region code. | `string` | `"lhr1"` | no |
| <a name="input_vercel_shared_env_vars"></a> [vercel\_shared\_env\_vars](#input\_vercel\_shared\_env\_vars) | Vercel environment variables shared across all three environments. Each entry's sensitive defaults to true (secure by default). | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, true)<br/>  }))</pre> | `[]` | no |
| <a name="input_vercel_team_id"></a> [vercel\_team\_id](#input\_vercel\_team\_id) | Vercel team ID. Required when enable\_vercel = true. Empty = saas.stacks.<stack>.vercel.team\_id, else saas.defaults.vercel.team\_id. | `string` | `""` | no |
| <a name="input_vercel_uat_env_vars"></a> [vercel\_uat\_env\_vars](#input\_vercel\_uat\_env\_vars) | Vercel environment variables for the UAT custom environment. Each entry's sensitive defaults to true (secure by default). | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, true)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bridge_version"></a> [bridge\_version](#output\_bridge\_version) | Rotation counter for the workload secret bridge (saas.bridge\_rotation, default 1). Non-sensitive: a bridging workload reads it as its write-only *\_wo\_version. |
| <a name="output_cross_cloud_injected_env_keys"></a> [cross\_cloud\_injected\_env\_keys](#output\_cross\_cloud\_injected\_env\_keys) | Vercel shared env var keys injected from cross\_cloud\_references. Empty when the frontend-URL seam is unused. |
| <a name="output_stack"></a> [stack](#output\_stack) | The SaaS stack key this workspace deploys (saas.stacks.<stack>). |
| <a name="output_supabase_anon_key"></a> [supabase\_anon\_key](#output\_supabase\_anon\_key) | The Supabase anon key (public credential). Null when enable\_supabase = false. |
| <a name="output_supabase_api_url"></a> [supabase\_api\_url](#output\_supabase\_api\_url) | The Supabase project REST API URL. Null when enable\_supabase = false. |
| <a name="output_supabase_database_password"></a> [supabase\_database\_password](#output\_supabase\_database\_password) | The initial Supabase database password. Null when enable\_supabase = false. |
| <a name="output_supabase_project_id"></a> [supabase\_project\_id](#output\_supabase\_project\_id) | The Supabase project ref. Null when enable\_supabase = false. |
| <a name="output_supabase_service_role_key"></a> [supabase\_service\_role\_key](#output\_supabase\_service\_role\_key) | The Supabase service role key. Treat as a secret. Null when enable\_supabase = false. |
| <a name="output_vault_managed_secret_names"></a> [vault\_managed\_secret\_names](#output\_vault\_managed\_secret\_names) | Names of vault secrets managed by this root. Null when enable\_vault\_secrets = false. |
| <a name="output_vercel_project_id"></a> [vercel\_project\_id](#output\_vercel\_project\_id) | The Vercel project ID. Null when enable\_vercel = false. |
| <a name="output_vercel_uat_environment_id"></a> [vercel\_uat\_environment\_id](#output\_vercel\_uat\_environment\_id) | The Vercel UAT custom environment ID. Null when enable\_vercel = false. |
<!-- END_TF_DOCS -->
