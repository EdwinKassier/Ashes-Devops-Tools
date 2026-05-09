# Vercel Project Module

Creates a Vercel project configured with three environments (QA/preview, UAT/custom, production), environment variables with drift-resistance, and domain assignments.

## Sensitive Environment Variable Drift

Vercel's API does not return sensitive variable values after creation. This module uses `terraform_data` resources with `replace_triggered_by` to force re-creation of env vars when values change, preventing silent drift.

## UAT Custom Environment

The UAT environment is a Vercel [Custom Environment](https://vercel.com/docs/deployments/environments#custom-environments). Vercel Pro plan allows **1 custom environment per project** — this slot is consumed by UAT.

## ignore_command (POSIX sh)

The `ignore_command` is executed by Vercel in `/bin/sh`, not bash. The module generates it using `[ ]` and `=` (POSIX sh), not `[[ ]]` or `==`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	github_repo = 
	project_name = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_vercel"></a> [vercel](#requirement\_vercel) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_vercel"></a> [vercel](#provider\_vercel) | 4.8.2 |



## Resources

The following resources are created:


- resource.terraform_data.prod_vars_version (modules/vercel/project/main.tf#L129)
- resource.terraform_data.qa_vars_version (modules/vercel/project/main.tf#L121)
- resource.terraform_data.shared_vars_version (modules/vercel/project/main.tf#L133)
- resource.terraform_data.uat_vars_version (modules/vercel/project/main.tf#L125)
- resource.vercel_custom_environment.uat (modules/vercel/project/main.tf#L107)
- resource.vercel_project.this (modules/vercel/project/main.tf#L88)
- resource.vercel_project_domain.prod (modules/vercel/project/main.tf#L235)
- resource.vercel_project_domain.qa (modules/vercel/project/main.tf#L213)
- resource.vercel_project_domain.uat (modules/vercel/project/main.tf#L226)
- resource.vercel_project_environment_variable.prod (modules/vercel/project/main.tf#L178)
- resource.vercel_project_environment_variable.qa (modules/vercel/project/main.tf#L139)
- resource.vercel_project_environment_variable.shared (modules/vercel/project/main.tf#L195)
- resource.vercel_project_environment_variable.uat (modules/vercel/project/main.tf#L160)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository in 'org/repo' format (e.g. 'myorg/myrepo'). | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Vercel project name. Lowercase alphanumeric and hyphens; 2–100 characters; must not start or end with a hyphen. | `string` | n/a | yes |
| <a name="input_allowed_branches"></a> [allowed\_branches](#input\_allowed\_branches) | Git branches that trigger deployments. Builds on all other branches are skipped.<br/>The module generates an ignore\_command using POSIX sh syntax (not bash) — Vercel<br/>executes this in /bin/sh. Do not add bash-specific syntax ([[ ]], ==).<br/>Must contain at least one branch name. | `list(string)` | <pre>[<br/>  "main"<br/>]</pre> | no |
| <a name="input_domains"></a> [domains](#input\_domains) | Domain assignments for the project. Each entry maps a domain to an environment.<br/>environment must be one of: "qa", "uat", "production". | <pre>list(object({<br/>    domain      = string<br/>    environment = string<br/>  }))</pre> | `[]` | no |
| <a name="input_framework"></a> [framework](#input\_framework) | Framework preset applied to the Vercel project. Set null for framework-agnostic projects. | `string` | `"nextjs"` | no |
| <a name="input_prod_environment_variables"></a> [prod\_environment\_variables](#input\_prod\_environment\_variables) | Environment variables for the production environment. key and value are required; sensitive defaults to false. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_production_branch"></a> [production\_branch](#input\_production\_branch) | Git branch to deploy to the production environment.<br/>⚠️  Must be an existing branch — Vercel validates branch existence at apply time.<br/>Setting a non-existent branch name will fail. Default "main" is safe for most repos. | `string` | `"main"` | no |
| <a name="input_qa_environment_variables"></a> [qa\_environment\_variables](#input\_qa\_environment\_variables) | Environment variables for the QA (preview) environment. key and value are required; sensitive defaults to false. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_root_directory"></a> [root\_directory](#input\_root\_directory) | Root directory of the project within the repository (e.g. "apps/nextjs" for a monorepo).<br/>Leave empty ("") for the repository root. The module converts "" to null internally —<br/>the Vercel API rejects an empty string with invalid\_root\_directory. | `string` | `""` | no |
| <a name="input_serverless_function_region"></a> [serverless\_function\_region](#input\_serverless\_function\_region) | Region for serverless function execution. Must be a valid Vercel function region code. | `string` | `"lhr1"` | no |
| <a name="input_shared_environment_variables"></a> [shared\_environment\_variables](#input\_shared\_environment\_variables) | Environment variables applied to all three environments (QA, UAT, production). Useful for SSL certs and global feature flags. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_team_id"></a> [team\_id](#input\_team\_id) | Vercel team ID. Required for team-owned projects. Leave empty for personal account projects. | `string` | `""` | no |
| <a name="input_uat_environment_variables"></a> [uat\_environment\_variables](#input\_uat\_environment\_variables) | Environment variables for the UAT custom environment. key and value are required; sensitive defaults to false. | <pre>list(object({<br/>    key       = string<br/>    value     = string<br/>    sensitive = optional(bool, false)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The Vercel project ID (prj\_xxx format). |
| <a name="output_project_name"></a> [project\_name](#output\_project\_name) | The Vercel project name. |
| <a name="output_uat_environment_id"></a> [uat\_environment\_id](#output\_uat\_environment\_id) | The Vercel custom environment ID for the UAT environment. Pass to vercel\_project\_domain or additional env var resources targeting UAT. |
<!-- END_TF_DOCS -->
