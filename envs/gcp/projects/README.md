# `envs/gcp/projects` (workspace `gcp-projects`)

Host and spoke projects for each environment, plus the `environment_config` contract that `gcp-workload-<env>` reads. It reads the `gcp-bootstrap` and `gcp-organization` contracts. Apply it after `gcp-organization` and before `gcp-network-hub`. Most inputs default to a key in `config/landing-zone.yaml`; an explicit variable (tfvars or an HCP Terraform workspace variable) wins over the config file. The description of each input names its config key.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 8.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bootstrap_contract"></a> [bootstrap\_contract](#input\_bootstrap\_contract) | gcp-bootstrap stage contract, the same type in every gcp root: admin\_project\_id, admin\_project\_number, terraform\_admin\_email, suffix, plus the optional automation identities (workload\_service\_accounts, stage\_service\_accounts, workload/network\_folder\_roles, delegated\_workload/network\_folder\_roles; omitted = no grants) and guardrail\_owner\_mode. This root needs: admin\_project\_id, suffix. Null = gcp.contracts.bootstrap from config/landing-zone.yaml, else the contract output of the gcp-bootstrap workspace. | <pre>object({<br/>    admin_project_id                = string<br/>    admin_project_number            = optional(string)<br/>    terraform_admin_email           = optional(string)<br/>    suffix                          = optional(string)<br/>    workload_service_accounts       = optional(map(object({ plan = string, apply = string })), {})<br/>    stage_service_accounts          = optional(map(object({ plan = string, apply = string })), {})<br/>    workload_folder_roles           = optional(object({ plan = list(string), apply = list(string) }), { plan = [], apply = [] })<br/>    network_folder_roles            = optional(object({ plan = list(string), apply = list(string) }), { plan = [], apply = [] })<br/>    delegated_workload_folder_roles = optional(list(string), [])<br/>    delegated_network_folder_roles  = optional(list(string), [])<br/>    guardrail_owner_mode            = optional(string, "separate")<br/>    # gcp-organization's plan-time checks read these (omitted = null, no check).<br/>    organization_apply_grantable_roles = optional(list(string))<br/>    organization_admin_members         = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_bootstrap_workspace_name"></a> [bootstrap\_workspace\_name](#input\_bootstrap\_workspace\_name) | Name of the gcp-bootstrap TFC workspace (read via remote state for admin\_project\_id and suffix). | `string` | `"gcp-bootstrap"` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2. | `string` | `null` | no |
| <a name="input_enable_network_connectivity_center"></a> [enable\_network\_connectivity\_center](#input\_enable\_network\_connectivity\_center) | Enable networkconnectivity.googleapis.com on the hub project and every environment host project, for the opt-in NCC hub/spoke connectivity. Null = true when config/landing-zone.yaml turns NCC on (gcp.network.ncc\_hub.enabled, gcp.network.connectivity = ncc, or any gcp.environments.<env>.network\_connectivity = ncc), else false. | `bool` | `null` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of application environment definitions. is\_production (default false here; required on every gcp.environments entry in config/landing-zone.yaml) is surfaced as environment\_config[<env>].is\_production for the gcp-workload guardrail checks. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin). | <pre>map(object({<br/>    display_name            = string<br/>    region                  = string<br/>    cidr_block              = string<br/>    budget_monthly_limit    = number<br/>    iam_group_role_bindings = map(set(string))<br/>    labels                  = optional(map(string), {})<br/>    is_production           = optional(bool, false)<br/>  }))</pre> | `null` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; "" disables the lookup. Read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_organization_contract"></a> [organization\_contract](#input\_organization\_contract) | gcp-organization stage contract, the same type in every gcp root: org\_id (numeric), billing\_account (billingAccounts/XXXXXX-XXXXXX-XXXXXX or bare ID), admin\_project\_number, folders (key => {id, name, display\_name}), tag\_values (key => tag value ID) and scoped\_access\_policy\_ids (env => policy ID). This root needs: billing\_account, folders, tag\_values (environment-<env>). Null = gcp.contracts.organization from config/landing-zone.yaml, else the contract output of the gcp-organization workspace. | <pre>object({<br/>    org_id               = optional(string)<br/>    billing_account      = optional(string)<br/>    admin_project_number = optional(string)<br/>    folders = optional(map(object({<br/>      id           = string<br/>      name         = string<br/>      display_name = string<br/>    })), {})<br/>    tag_values               = optional(map(string), {})<br/>    scoped_access_policy_ids = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_organization_name"></a> [organization\_name](#input\_organization\_name) | Name of the organization. Null = org.display\_name from config/landing-zone.yaml, else "My Organization". | `string` | `null` | no |
| <a name="input_organization_workspace_name"></a> [organization\_workspace\_name](#input\_organization\_workspace\_name) | Name of the gcp-organization TFC workspace (read via remote state for folders, tag values, and billing account). | `string` | `"gcp-organization"` | no |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix prepended to all GCP project IDs. Null = org.prefix from config/landing-zone.yaml (shared by every GCP root). | `string` | `null` | no |
| <a name="input_project_services"></a> [project\_services](#input\_project\_services) | List of APIs to enable on all projects | `list(string)` | <pre>[<br/>  "cloudresourcemanager.googleapis.com",<br/>  "compute.googleapis.com",<br/>  "serviceusage.googleapis.com",<br/>  "iam.googleapis.com",<br/>  "cloudbilling.googleapis.com",<br/>  "monitoring.googleapis.com"<br/>]</pre> | no |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | OPTIONAL SA for the providers to impersonate, for deliberate LOCAL human runs only. Leave null in Terraform Cloud: dynamic credentials already authenticate plan as <prefix>-projects-plan and apply as <prefix>-projects-apply. | `string` | `null` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization that owns the upstream workspaces read via remote state. Null = org.tfc.organization from config/landing-zone.yaml. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_automation_folder_grants"></a> [automation\_folder\_grants](#output\_automation\_folder\_grants) | Deprecated: read contract.automation\_folder\_grants (removed in v1.0). Folder IAM grants made to the workload / network-hub automation SAs. |
| <a name="output_contract"></a> [contract](#output\_contract) | The gcp-projects cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0. |
| <a name="output_environment_config"></a> [environment\_config](#output\_environment\_config) | Deprecated: read contract.environment\_config (removed in v1.0). Per-environment config: folder, host project, region, CIDR, labels, environment tag value, is\_production, and the environment's folder-scoped VPC-SC access policy ID. |
| <a name="output_project_ids"></a> [project\_ids](#output\_project\_ids) | Deprecated: read contract.project\_ids (removed in v1.0). Map of project key (e.g. 'shared-hub', '<env>-host') to project ID. |
| <a name="output_project_numbers"></a> [project\_numbers](#output\_project\_numbers) | Deprecated: read contract.project\_numbers (removed in v1.0). Map of project key to numeric project number. |
| <a name="output_projects"></a> [projects](#output\_projects) | Deprecated: read contract.projects (removed in v1.0). Map of created projects. |
<!-- END_TF_DOCS -->
