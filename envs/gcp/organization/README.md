# Organization Root

`envs/gcp/organization` is the control-plane root for the platform. It creates the admin project, organization/folder policy, shared hub projects, per-environment host projects, and the downstream contract consumed by `envs/gcp/workload`.

## What It Creates

- One admin project for Terraform automation and workload identity
- One shared services folder containing the hub and DNS projects
- One folder and host project per entry in `var.environments`
- Centralized org policy, audit logging, tags, and platform budgets

## Source Of Truth

Application environments are declared once through `var.environments`. Each entry must provide:

- `display_name`
- `region`
- `cidr_block`
- `budget_monthly_limit`
- `iam_group_role_bindings`
- `labels`

See [`terraform.tfvars.example`](./terraform.tfvars.example) for the expected shape.

## Tuning inputs: `gcp_overrides`

Every other input of the organization stage is one object, `gcp_overrides`, of
the stage's `gcp` type. The effective value is the gcp section of
`config/landing-zone.yaml` with the set (non-null) override keys on top:
`merge(local.lz_gcp, { for k, v in var.gcp_overrides : k => v if v != null })`.
So a set key wins over the config file, and an unset or null key keeps the
config value, else the stage default. Keys outside the config schema (for
example `enable_pam`, `logging_project_id`) are set only here.

```hcl
gcp_overrides = {
  enable_pam          = true
  pam_eligible_groups = ["gcp-org-admin-requesters@example.com"]
  pam_approver_groups = ["gcp-org-admin-approvers@example.com"]
}
```

The variable names before this change map 1:1 to keys (UPGRADING.md).

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules


- organization - ../../../modules/gcp/stages/organization


## Resources

The following resources are created:


- resource.terraform_data.removed_inputs_guard (envs/gcp/organization/deprecated_inputs.tf#L292)
- resource.terraform_data.starter_requires_budget (envs/gcp/organization/main.tf#L104)
- data source.google_billing_account.billing (envs/gcp/organization/data.tf#L33)
- data source.google_organization.org (envs/gcp/organization/data.tf#L27)
- data source.terraform_remote_state.gcp_bootstrap (envs/gcp/organization/data.tf#L15)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | REMOVED in v0.2.0: use gcp\_overrides.admin\_email. | `any` | `null` | no |
| <a name="input_alert_notification_channels"></a> [alert\_notification\_channels](#input\_alert\_notification\_channels) | REMOVED in v0.2.0: use gcp\_overrides.alert\_notification\_channels. | `any` | `null` | no |
| <a name="input_alert_notification_emails"></a> [alert\_notification\_emails](#input\_alert\_notification\_emails) | REMOVED in v0.2.0: use gcp\_overrides.alert\_notification\_emails. | `any` | `null` | no |
| <a name="input_allow_user_principals_for_break_glass"></a> [allow\_user\_principals\_for\_break\_glass](#input\_allow\_user\_principals\_for\_break\_glass) | REMOVED in v0.2.0: use gcp\_overrides.allow\_user\_principals\_for\_break\_glass. | `any` | `null` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | REMOVED in v0.2.0: use gcp\_overrides.allowed\_regions. | `any` | `null` | no |
| <a name="input_allowed_workload_identity_aws_accounts"></a> [allowed\_workload\_identity\_aws\_accounts](#input\_allowed\_workload\_identity\_aws\_accounts) | REMOVED in v0.2.0: use gcp\_overrides.allowed\_workload\_identity\_aws\_accounts. | `any` | `null` | no |
| <a name="input_allowed_workload_identity_issuers"></a> [allowed\_workload\_identity\_issuers](#input\_allowed\_workload\_identity\_issuers) | REMOVED in v0.2.0: use gcp\_overrides.allowed\_workload\_identity\_issuers. | `any` | `null` | no |
| <a name="input_audit_soft_delete_retention_days"></a> [audit\_soft\_delete\_retention\_days](#input\_audit\_soft\_delete\_retention\_days) | REMOVED in v0.2.0: use gcp\_overrides.audit\_soft\_delete\_retention\_days. | `any` | `null` | no |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account ID (optional if billing\_account\_display\_name is provided). Null = gcp.billing\_account from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_billing_account_display_name"></a> [billing\_account\_display\_name](#input\_billing\_account\_display\_name) | Display name of the billing account (used if billing\_account ID is not provided) | `string` | `null` | no |
| <a name="input_billing_admin_groups"></a> [billing\_admin\_groups](#input\_billing\_admin\_groups) | REMOVED in v0.2.0: use gcp\_overrides.billing\_admin\_groups. | `any` | `null` | no |
| <a name="input_billing_contact_email"></a> [billing\_contact\_email](#input\_billing\_contact\_email) | REMOVED in v0.2.0: use gcp\_overrides.billing\_contact\_email. | `any` | `null` | no |
| <a name="input_bootstrap_contract"></a> [bootstrap\_contract](#input\_bootstrap\_contract) | gcp-bootstrap stage contract, the same type in every gcp root: admin\_project\_id, admin\_project\_number, terraform\_admin\_email, suffix, plus the optional automation identities (workload\_service\_accounts, stage\_service\_accounts, workload/network\_folder\_roles, delegated\_workload/network\_folder\_roles; omitted = no grants) and guardrail\_owner\_mode. This root needs: admin\_project\_id, admin\_project\_number, terraform\_admin\_email. Null = gcp.contracts.bootstrap from config/landing-zone.yaml, else the contract output of the gcp-bootstrap workspace. | <pre>object({<br/>    admin_project_id                = string<br/>    admin_project_number            = optional(string)<br/>    terraform_admin_email           = optional(string)<br/>    suffix                          = optional(string)<br/>    workload_service_accounts       = optional(map(object({ plan = string, apply = string })), {})<br/>    stage_service_accounts          = optional(map(object({ plan = string, apply = string })), {})<br/>    workload_folder_roles           = optional(object({ plan = list(string), apply = list(string) }), { plan = [], apply = [] })<br/>    network_folder_roles            = optional(object({ plan = list(string), apply = list(string) }), { plan = [], apply = [] })<br/>    delegated_workload_folder_roles = optional(list(string), [])<br/>    delegated_network_folder_roles  = optional(list(string), [])<br/>    guardrail_owner_mode            = optional(string, "separate")<br/>  })</pre> | `null` | no |
| <a name="input_bootstrap_workspace_name"></a> [bootstrap\_workspace\_name](#input\_bootstrap\_workspace\_name) | Name of the gcp-bootstrap TFC workspace this root reads via remote state for the admin project, Terraform admin SA, and WIF pools. | `string` | `"gcp-bootstrap"` | no |
| <a name="input_break_glass_principal_emails"></a> [break\_glass\_principal\_emails](#input\_break\_glass\_principal\_emails) | REMOVED in v0.2.0: use gcp\_overrides.break\_glass\_principal\_emails. | `any` | `null` | no |
| <a name="input_break_glass_user"></a> [break\_glass\_user](#input\_break\_glass\_user) | REMOVED in v0.2.0: use gcp\_overrides.break\_glass\_user. | `any` | `null` | no |
| <a name="input_budget_currency"></a> [budget\_currency](#input\_budget\_currency) | REMOVED in v0.2.0: use gcp\_overrides.budget\_currency. | `any` | `null` | no |
| <a name="input_cmek_required_services"></a> [cmek\_required\_services](#input\_cmek\_required\_services) | REMOVED in v0.2.0: use gcp\_overrides.cmek\_required\_services. | `any` | `null` | no |
| <a name="input_containment_exempt_principals"></a> [containment\_exempt\_principals](#input\_containment\_exempt\_principals) | REMOVED in v0.2.0: use gcp\_overrides.containment\_exempt\_principals. | `any` | `null` | no |
| <a name="input_custom_org_constraints"></a> [custom\_org\_constraints](#input\_custom\_org\_constraints) | REMOVED in v0.2.0: use gcp\_overrides.custom\_org\_constraints. | `any` | `null` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2. | `string` | `null` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | The domain name of the organization (e.g., 'example.com'). Null = org.domain from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_enable_admin_containment"></a> [enable\_admin\_containment](#input\_enable\_admin\_containment) | REMOVED in v0.2.0: use gcp\_overrides.enable\_admin\_containment. | `any` | `null` | no |
| <a name="input_enable_audit_bucket_lock"></a> [enable\_audit\_bucket\_lock](#input\_enable\_audit\_bucket\_lock) | REMOVED in v0.2.0: use gcp\_overrides.enable\_audit\_bucket\_lock. | `any` | `null` | no |
| <a name="input_enable_cis_log_metrics"></a> [enable\_cis\_log\_metrics](#input\_enable\_cis\_log\_metrics) | REMOVED in v0.2.0: use gcp\_overrides.enable\_cis\_log\_metrics. | `any` | `null` | no |
| <a name="input_enable_cmek_org_policy"></a> [enable\_cmek\_org\_policy](#input\_enable\_cmek\_org\_policy) | REMOVED in v0.2.0: use gcp\_overrides.enable\_cmek\_org\_policy. | `any` | `null` | no |
| <a name="input_enable_control_plane_alerting"></a> [enable\_control\_plane\_alerting](#input\_enable\_control\_plane\_alerting) | REMOVED in v0.2.0: use gcp\_overrides.enable\_control\_plane\_alerting. | `any` | `null` | no |
| <a name="input_enable_legacy_admin_folder_roles"></a> [enable\_legacy\_admin\_folder\_roles](#input\_enable\_legacy\_admin\_folder\_roles) | REMOVED in v0.2.0: use gcp\_overrides.enable\_legacy\_admin\_folder\_roles. | `any` | `null` | no |
| <a name="input_enable_log_analytics"></a> [enable\_log\_analytics](#input\_enable\_log\_analytics) | REMOVED in v0.2.0: use gcp\_overrides.enable\_log\_analytics. | `any` | `null` | no |
| <a name="input_enable_logging_organization_settings"></a> [enable\_logging\_organization\_settings](#input\_enable\_logging\_organization\_settings) | REMOVED in v0.2.0: use gcp\_overrides.enable\_logging\_organization\_settings. | `any` | `null` | no |
| <a name="input_enable_pam"></a> [enable\_pam](#input\_enable\_pam) | REMOVED in v0.2.0: use gcp\_overrides.enable\_pam. | `any` | `null` | no |
| <a name="input_enable_principal_access_boundary"></a> [enable\_principal\_access\_boundary](#input\_enable\_principal\_access\_boundary) | REMOVED in v0.2.0: use gcp\_overrides.enable\_principal\_access\_boundary. | `any` | `null` | no |
| <a name="input_enable_scoped_access_policies"></a> [enable\_scoped\_access\_policies](#input\_enable\_scoped\_access\_policies) | REMOVED in v0.2.0: use gcp\_overrides.enable\_scoped\_access\_policies. | `any` | `null` | no |
| <a name="input_enforce_os_login"></a> [enforce\_os\_login](#input\_enforce\_os\_login) | REMOVED in v0.2.0: use gcp\_overrides.enforce\_os\_login. | `any` | `null` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of application environment definitions. is\_production (default false) marks production environments: it drives the production guardrail checks here and in gcp-bootstrap / gcp-workload. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin). | <pre>map(object({<br/>    display_name            = string<br/>    region                  = string<br/>    cidr_block              = string<br/>    budget_monthly_limit    = number<br/>    iam_group_role_bindings = map(set(string))<br/>    labels                  = optional(map(string), {})<br/>    is_production           = optional(bool, false)<br/>  }))</pre> | `null` | no |
| <a name="input_gcp_overrides"></a> [gcp\_overrides](#input\_gcp\_overrides) | Explicit overrides of the gcp section (config/landing-zone.yaml gcp.*) fed to the organization stage. Every key is optional and the type is the stage's gcp object: a set (non-null) key wins over the config file, an unset or null key keeps the config value, else the stage default. Keys that are not in the config schema (enable\_pam, logging\_project\_id, ...) are set only here. Precedence: gcp\_overrides > config/landing-zone.yaml > built-in default. See UPGRADING.md for the old variable names. | <pre>object({<br/>    admin_email                           = optional(string)<br/>    break_glass_user                      = optional(string)<br/>    organization_admin_groups             = optional(list(string))<br/>    billing_admin_groups                  = optional(list(string))<br/>    allow_user_principals_for_break_glass = optional(bool)<br/>    allowed_regions                       = optional(list(string))<br/>    strict_folder_policy_environment_keys = optional(list(string))<br/>    enforce_os_login                      = optional(bool)<br/>    os_login_exempt_environment_keys      = optional(list(string))<br/>    security_contact_email                = optional(string)<br/>    billing_contact_email                 = optional(string)<br/>    budget_currency                       = optional(string)<br/>    logging_project_id                    = optional(string)<br/>    logging_project_number                = optional(string)<br/>    audit_soft_delete_retention_days      = optional(number)<br/>    enable_control_plane_alerting         = optional(bool)<br/>    enable_cis_log_metrics                = optional(bool)<br/>    alert_notification_emails             = optional(list(string))<br/>    alert_notification_channels           = optional(list(string))<br/>    break_glass_principal_emails          = optional(list(string))<br/>    custom_org_constraints = optional(list(object({<br/>      name           = string<br/>      display_name   = string<br/>      description    = string<br/>      action_type    = string<br/>      condition      = string<br/>      method_types   = list(string)<br/>      resource_types = list(string)<br/>      enforcement    = optional(string, "enforce")<br/>    })))<br/>    enable_audit_bucket_lock = optional(bool)<br/>    iam_deny_policies = optional(list(object({<br/>      name         = string<br/>      display_name = optional(string)<br/>      rules = list(object({<br/>        description           = optional(string)<br/>        denied_principals     = list(string)<br/>        denied_permissions    = list(string)<br/>        exception_principals  = optional(list(string), [])<br/>        exception_permissions = optional(list(string), [])<br/>        denial_condition = optional(object({<br/>          expression  = string<br/>          title       = optional(string)<br/>          description = optional(string)<br/>        }))<br/>      }))<br/>    })))<br/>    enable_cmek_org_policy                      = optional(bool)<br/>    cmek_required_services                      = optional(list(string))<br/>    enable_admin_containment                    = optional(bool)<br/>    containment_exempt_principals               = optional(list(string))<br/>    enable_legacy_admin_folder_roles            = optional(bool)<br/>    enable_scoped_access_policies               = optional(bool)<br/>    enable_pam                                  = optional(bool)<br/>    pam_eligible_groups                         = optional(list(string))<br/>    pam_approver_groups                         = optional(list(string))<br/>    pam_max_request_duration                    = optional(string)<br/>    guardrail_owner_mode                        = optional(string)<br/>    prefer_managed_constraints                  = optional(bool)<br/>    enable_log_analytics                        = optional(bool)<br/>    log_analytics_retention_days                = optional(number)<br/>    enable_logging_organization_settings        = optional(bool)<br/>    scc_api_version                             = optional(string)<br/>    logging_settings_kms_key_name               = optional(string)<br/>    enable_principal_access_boundary            = optional(bool)<br/>    principal_access_boundary_allowed_resources = optional(list(string))<br/>    restrict_cloud_run_ingress                  = optional(bool)<br/>    allowed_workload_identity_issuers           = optional(list(string))<br/>    allowed_workload_identity_aws_accounts      = optional(list(string))<br/>    org_policy_overrides = optional(map(object({<br/>      enforce        = optional(bool)<br/>      allowed_values = optional(list(string))<br/>      denied_values  = optional(list(string))<br/>      allow_all      = optional(bool)<br/>      deny_all       = optional(bool)<br/>      disabled       = optional(bool, false)<br/>    })))<br/>    wif_tenant_pin_enforcement = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#input\_guardrail\_owner\_mode) | REMOVED in v0.2.0: use gcp\_overrides.guardrail\_owner\_mode. | `any` | `null` | no |
| <a name="input_iam_deny_policies"></a> [iam\_deny\_policies](#input\_iam\_deny\_policies) | REMOVED in v0.2.0: use gcp\_overrides.iam\_deny\_policies. | `any` | `null` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; "" disables the lookup. Read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_log_analytics_retention_days"></a> [log\_analytics\_retention\_days](#input\_log\_analytics\_retention\_days) | REMOVED in v0.2.0: use gcp\_overrides.log\_analytics\_retention\_days. | `any` | `null` | no |
| <a name="input_logging_project_id"></a> [logging\_project\_id](#input\_logging\_project\_id) | REMOVED in v0.2.0: use gcp\_overrides.logging\_project\_id. | `any` | `null` | no |
| <a name="input_logging_project_number"></a> [logging\_project\_number](#input\_logging\_project\_number) | REMOVED in v0.2.0: use gcp\_overrides.logging\_project\_number. | `any` | `null` | no |
| <a name="input_logging_settings_kms_key_name"></a> [logging\_settings\_kms\_key\_name](#input\_logging\_settings\_kms\_key\_name) | REMOVED in v0.2.0: use gcp\_overrides.logging\_settings\_kms\_key\_name. | `any` | `null` | no |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly budget limit for the organization. Set to 0 to disable budget alerts (rejected for the starter profile). Null = org.monthly\_budget\_usd from config/landing-zone.yaml (starter profile only), else 1000 (production) / unset (starter, which then fails the plan). | `number` | `null` | no |
| <a name="input_org_policy_overrides"></a> [org\_policy\_overrides](#input\_org\_policy\_overrides) | REMOVED in v0.2.0: use gcp\_overrides.org\_policy\_overrides. | `any` | `null` | no |
| <a name="input_organization_admin_groups"></a> [organization\_admin\_groups](#input\_organization\_admin\_groups) | REMOVED in v0.2.0: use gcp\_overrides.organization\_admin\_groups. | `any` | `null` | no |
| <a name="input_organization_name"></a> [organization\_name](#input\_organization\_name) | Name of the organization. Null = org.display\_name from config/landing-zone.yaml, else "My Organization". | `string` | `null` | no |
| <a name="input_os_login_exempt_environment_keys"></a> [os\_login\_exempt\_environment\_keys](#input\_os\_login\_exempt\_environment\_keys) | REMOVED in v0.2.0: use gcp\_overrides.os\_login\_exempt\_environment\_keys. | `any` | `null` | no |
| <a name="input_pam_approver_groups"></a> [pam\_approver\_groups](#input\_pam\_approver\_groups) | REMOVED in v0.2.0: use gcp\_overrides.pam\_approver\_groups. | `any` | `null` | no |
| <a name="input_pam_eligible_groups"></a> [pam\_eligible\_groups](#input\_pam\_eligible\_groups) | REMOVED in v0.2.0: use gcp\_overrides.pam\_eligible\_groups. | `any` | `null` | no |
| <a name="input_pam_max_request_duration"></a> [pam\_max\_request\_duration](#input\_pam\_max\_request\_duration) | REMOVED in v0.2.0: use gcp\_overrides.pam\_max\_request\_duration. | `any` | `null` | no |
| <a name="input_pin_wif_to_tfc_organization"></a> [pin\_wif\_to\_tfc\_organization](#input\_pin\_wif\_to\_tfc\_organization) | Enforce (custom org-policy constraint) that every HCP Terraform workload identity provider references tfc\_organization in its attribute\_condition, so no pipeline can trust another TFC organization. Default true. | `bool` | `true` | no |
| <a name="input_prefer_managed_constraints"></a> [prefer\_managed\_constraints](#input\_prefer\_managed\_constraints) | REMOVED in v0.2.0: use gcp\_overrides.prefer\_managed\_constraints. | `any` | `null` | no |
| <a name="input_principal_access_boundary_allowed_resources"></a> [principal\_access\_boundary\_allowed\_resources](#input\_principal\_access\_boundary\_allowed\_resources) | REMOVED in v0.2.0: use gcp\_overrides.principal\_access\_boundary\_allowed\_resources. | `any` | `null` | no |
| <a name="input_profile"></a> [profile](#input\_profile) | Cost/assurance profile: production (default) or starter. starter requires a monthly budget (monthly\_budget\_amount or org.monthly\_budget\_usd) and alerts at 50/80/100% of it. Null = org.profile from config/landing-zone.yaml, else production. | `string` | `null` | no |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix prepended to all GCP project IDs to ensure global uniqueness.<br/>Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.<br/>Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and<br/>the prefix consumes part of that budget. Null = org.prefix from<br/>config/landing-zone.yaml (shared by every GCP root). The placeholder "my-org" is rejected. | `string` | `null` | no |
| <a name="input_restrict_cloud_run_ingress"></a> [restrict\_cloud\_run\_ingress](#input\_restrict\_cloud\_run\_ingress) | REMOVED in v0.2.0: use gcp\_overrides.restrict\_cloud\_run\_ingress. | `any` | `null` | no |
| <a name="input_security_contact_email"></a> [security\_contact\_email](#input\_security\_contact\_email) | REMOVED in v0.2.0: use gcp\_overrides.security\_contact\_email. | `any` | `null` | no |
| <a name="input_shared_iam_group_role_bindings"></a> [shared\_iam\_group\_role\_bindings](#input\_shared\_iam\_group\_role\_bindings) | Folder IAM bindings for the shared services folder, keyed by Google Group email | `map(set(string))` | `{}` | no |
| <a name="input_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#input\_strict\_folder\_policy\_environment\_keys) | REMOVED in v0.2.0: use gcp\_overrides.strict\_folder\_policy\_environment\_keys. | `any` | `null` | no |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | Service account email for the Terraform admin SA created by the bootstrap stage.<br/>The organization providers impersonate this SA for all API calls, ensuring that<br/>even local runs operate with the SA's permissions rather than the caller's personal<br/>credentials.<br/>Format: terraform-admin@<admin-project-id>.iam.gserviceaccount.com<br/>Set to null only during the very first bootstrap apply when the SA does not exist yet. | `string` | `null` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | HCP Terraform / Terraform Enterprise hostname whose dynamic-credential tokens the WIF pools trust (app.terraform.io, app.eu.terraform.io or your TFE host). | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization used for dynamic credentials. Null = org.tfc.organization from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_wif_github_owner_ids"></a> [wif\_github\_owner\_ids](#input\_wif\_github\_owner\_ids) | Numeric GitHub owner IDs a GitHub Actions workload identity provider may pin: its attribute\_condition must be exactly assertion.repository\_owner\_id == "<id>" for one of them. Empty (default) leaves GitHub providers tenant-unpinned (the issuer is still allow-listed). | `list(string)` | `[]` | no |
| <a name="input_wif_tenant_pin_enforcement"></a> [wif\_tenant\_pin\_enforcement](#input\_wif\_tenant\_pin\_enforcement) | REMOVED in v0.2.0: use gcp\_overrides.wif\_tenant\_pin\_enforcement. | `any` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_containment_enabled"></a> [admin\_containment\_enabled](#output\_admin\_containment\_enabled) | Deprecated: read contract.admin\_containment\_enabled (removed in v1.0). Whether the admin-containment deny policy is on (explicit enable\_admin\_containment, else gcp.admin\_containment, else on when any environment is\_production). |
| <a name="output_admin_project"></a> [admin\_project](#output\_admin\_project) | Deprecated: read contract.admin\_project (removed in v1.0). Details of the admin project |
| <a name="output_admin_project_number"></a> [admin\_project\_number](#output\_admin\_project\_number) | Deprecated: read contract.admin\_project\_number (removed in v1.0). Admin project number for Workload Identity pool references |
| <a name="output_audit_logs_bucket_name"></a> [audit\_logs\_bucket\_name](#output\_audit\_logs\_bucket\_name) | Deprecated: read contract.audit\_logs\_bucket\_name (removed in v1.0). Cloud Storage bucket receiving organization-wide audit logs |
| <a name="output_audit_project_id"></a> [audit\_project\_id](#output\_audit\_project\_id) | Deprecated: read contract.audit\_project\_id (removed in v1.0). Project holding the org audit bucket, audit CMEK and control-plane alerts (logging\_project\_id, or the admin project). |
| <a name="output_billing_account"></a> [billing\_account](#output\_billing\_account) | Deprecated: read contract.billing\_account (removed in v1.0). Billing account ID for downstream usage |
| <a name="output_billing_export_dataset_id"></a> [billing\_export\_dataset\_id](#output\_billing\_export\_dataset\_id) | Deprecated: read contract.billing\_export\_dataset\_id (removed in v1.0). BigQuery dataset ID for Cloud Billing export |
| <a name="output_cmek_key_names"></a> [cmek\_key\_names](#output\_cmek\_key\_names) | Deprecated: read contract.cmek\_key\_names (removed in v1.0). Map of CMEK key short-name to key ID created by the organization stage. Lets downstream roots (e.g. gcp/workload) encrypt resources with org-managed keys via remote state. Re-exports modules/gcp/stages/organization output cmek\_key\_names. |
| <a name="output_contract"></a> [contract](#output\_contract) | The gcp-organization cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0. |
| <a name="output_control_plane_alert_policy_ids"></a> [control\_plane\_alert\_policy\_ids](#output\_control\_plane\_alert\_policy\_ids) | Deprecated: read contract.control\_plane\_alert\_policy\_ids (removed in v1.0). Map of control-plane watch name to alert policy ID. |
| <a name="output_default_region"></a> [default\_region](#output\_default\_region) | Deprecated: read contract.default\_region (removed in v1.0). Default region for resources |
| <a name="output_delegated_folder_iam_targets"></a> [delegated\_folder\_iam\_targets](#output\_delegated\_folder\_iam\_targets) | Deprecated: read contract.delegated\_folder\_iam\_targets (removed in v1.0). Folders on which the gcp-projects apply SA holds the conditional folderIamAdmin, with each folder's role allow-list. |
| <a name="output_folders"></a> [folders](#output\_folders) | Deprecated: read contract.folders (removed in v1.0). Map of created folders |
| <a name="output_github_oidc_pool_id"></a> [github\_oidc\_pool\_id](#output\_github\_oidc\_pool\_id) | Deprecated: read contract.github\_oidc\_pool\_id (removed in v1.0). Workload Identity Pool ID for GitHub Actions OIDC |
| <a name="output_github_oidc_provider_name"></a> [github\_oidc\_provider\_name](#output\_github\_oidc\_provider\_name) | Deprecated: read contract.github\_oidc\_provider\_name (removed in v1.0). Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth) |
| <a name="output_guardrail_deny_policy_specs"></a> [guardrail\_deny\_policy\_specs](#output\_guardrail\_deny\_policy\_specs) | Deprecated: read contract.guardrail\_deny\_policy\_specs (removed in v1.0). DEPRECATED (removed in v1.0). gcloud policy-file JSON of the deny policies this root applies in the legacy organization mode; empty in separate mode, where gcp-guardrails owns them (its deny\_policy\_specs output serves the break-glass path). |
| <a name="output_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#output\_guardrail\_owner\_mode) | Deprecated: read contract.guardrail\_owner\_mode (removed in v1.0). Deny-policy ownership: "separate" (authored and applied by the gcp-guardrails root) or "organization" (legacy: applied by this root). |
| <a name="output_log_analytics_bucket_id"></a> [log\_analytics\_bucket\_id](#output\_log\_analytics\_bucket\_id) | Deprecated: read contract.log\_analytics\_bucket\_id (removed in v1.0). Audit Log Analytics bucket (null when disabled). |
| <a name="output_org_id"></a> [org\_id](#output\_org\_id) | Deprecated: read contract.org\_id (removed in v1.0). Organization ID for downstream resource configuration |
| <a name="output_organization"></a> [organization](#output\_organization) | Deprecated: read contract.organization (removed in v1.0). Organization details |
| <a name="output_organization_name"></a> [organization\_name](#output\_organization\_name) | Deprecated: read contract.organization\_name (removed in v1.0). Name of the organization |
| <a name="output_pam_entitlement_name"></a> [pam\_entitlement\_name](#output\_pam\_entitlement\_name) | Deprecated: read contract.pam\_entitlement\_name (removed in v1.0). Resource name of the just-in-time org-admin PAM entitlement (null when enable\_pam = false). |
| <a name="output_principal_access_boundary_policy"></a> [principal\_access\_boundary\_policy](#output\_principal\_access\_boundary\_policy) | Deprecated: read contract.principal\_access\_boundary\_policy (removed in v1.0). Automation principal access boundary policy name (null when disabled). |
| <a name="output_project_prefix"></a> [project\_prefix](#output\_project\_prefix) | Deprecated: read contract.project\_prefix (removed in v1.0). Project prefix used for naming |
| <a name="output_scc_pubsub_topic_id"></a> [scc\_pubsub\_topic\_id](#output\_scc\_pubsub\_topic\_id) | Deprecated: read contract.scc\_pubsub\_topic\_id (removed in v1.0). Pub/Sub topic receiving Security Command Center findings |
| <a name="output_scoped_access_policy_ids"></a> [scoped\_access\_policy\_ids](#output\_scoped\_access\_policy\_ids) | Deprecated: read contract.scoped\_access\_policy\_ids (removed in v1.0). Map of environment key -> numeric ID of its folder-scoped Access Context Manager policy. |
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Deprecated: read contract.tag\_keys (removed in v1.0). Map of tag key short names to their Resource Manager resource IDs |
| <a name="output_tag_values"></a> [tag\_values](#output\_tag\_values) | Deprecated: read contract.tag\_values (removed in v1.0). Map of available Resource Manager Tag Values |
| <a name="output_terraform_service_account_email"></a> [terraform\_service\_account\_email](#output\_terraform\_service\_account\_email) | Deprecated: read contract.terraform\_service\_account\_email (removed in v1.0). Email of the Terraform Admin Service Account |
| <a name="output_tfc_oidc_pool_id"></a> [tfc\_oidc\_pool\_id](#output\_tfc\_oidc\_pool\_id) | Deprecated: read contract.tfc\_oidc\_pool\_id (removed in v1.0). Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured) |
| <a name="output_tfc_oidc_provider_name"></a> [tfc\_oidc\_provider\_name](#output\_tfc\_oidc\_provider\_name) | Deprecated: read contract.tfc\_oidc\_provider\_name (removed in v1.0). Fully-qualified WIF provider name for Terraform Cloud OIDC (null if TFC OIDC not configured) |
<!-- END_TF_DOCS -->
