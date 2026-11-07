# Bootstrap Module

The foundation of the entire landing zone. This module bootstraps the initial administrative validation and automation capabilities.

## Purpose

- Creates the `admin` project (the seed project)
- Enables core APIs required for Terraform to operate
- Creates the Terraform Admin Service Account (phase-0 human bootstrap + the `gcp-bootstrap` **apply** identity only)
- Creates **per-stage plan/apply service accounts** (Cloud Foundation Fabric FAST pattern, audit C2) — see `service_accounts.tf` for the role matrix
- Sets up Workload Identity Federation for Terraform Cloud (per workspace **and run phase**) and, opt-in, GitHub Actions

## Identity model (audit C2)

| Identity | Bound to (TFC) | Scope |
|---|---|---|
| `terraform-admin` | `gcp-bootstrap:apply` (+ human impersonation) | org `iam.securityAdmin` + org viewer; admin-project SA/WIF/serviceusage admin |
| `<prefix>-<stage>-plan` (bootstrap, organization, projects, network-hub) | `<workspace>:plan` | read-only (browser, org viewer, security reviewer, stage-specific viewers) |
| `<prefix>-organization-apply` | `gcp-organization:apply` | folders, org IAM, org policy, sinks, SCC notifications, tags, deny, contacts; admin-project KMS/GCS/PubSub/BQ/monitoring; billing costsManager |
| `<prefix>-projects-apply` | `gcp-projects:apply` | projectCreator, billing.projectManager/user, metrics scope; **conditional** folderIamAdmin limited to the workload/network folder roles |
| `<prefix>-network-hub-apply` | `gcp-network-hub:apply` | org ACM policyAdmin; network roles on the `shared` folder (granted by gcp-projects) |
| `<prefix>-wl-<env>-plan` / `-apply` | `gcp-workload-<env>:plan` / `:apply` | **no org-level role**; env-folder roles (granted by gcp-projects), billing budget roles, optional access-policy-scoped ACM |

The TFC provider maps `attribute.workspace_phase = <workspace_name>:<run_phase>` and `attribute.workspace_id_phase = <workspace_id>:<run_phase>`; each binding targets exactly one of these, so a speculative plan can only mint a read-only identity. The condition pins `terraform_organization_name` (and optionally `terraform_organization_id` and `terraform_project_id`).

## Usage

```hcl
module "bootstrap" {
  source = "../../modules/gcp/stages/bootstrap"

  org_id          = "123456789"
  billing_account = "000000-000000-000000"
  project_prefix  = "my-org"
  admin_email     = "admin@example.com"

  tfc_organization      = "my-tfc-org"
  workload_environments = ["dev", "prod"]
}
```

## Outputs consumed downstream

- `tfc_plan_service_accounts` / `tfc_apply_service_accounts` — workspace name -> SA email (tfc-admin sets `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` / `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL`)
- `tfc_workload_provider_name` — for `TFC_GCP_WORKLOAD_PROVIDER_NAME`
- `workload_service_accounts`, `stage_service_accounts`, `workload_folder_roles`, `network_folder_roles` — consumed by gcp-projects
- `admin_project_id`, `admin_project_number`, `terraform_admin_email`, `suffix` — unchanged contract

## Admin project

The admin project is created through the shared
[project primitive](../../project/README.md) (`module.admin_project`); the
`<prefix>-admin-<8 hex>` naming scheme stays in this stage. `moved.tf` moves the
former `google_project.admin_project` and `google_project_service.admin_project_services`
into the module, so upgrading replaces nothing.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	admin_email =
	billing_account =
	org_id =
	project_prefix =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules


- admin_project - ../../project
- gh_oidc - ../../iam/workload-identity
- terraform_admin_sa - ../../iam/service-account
- tfc_oidc - ../../iam/workload-identity


## Resources

The following resources are created:


- resource.google_access_context_manager_access_policy_iam_member.workload (modules/gcp/stages/bootstrap/service_accounts.tf#L306)
- resource.google_billing_account_iam_member.stage_billing_roles (modules/gcp/stages/bootstrap/service_accounts.tf#L296)
- resource.google_organization_iam_custom_role.plan_viewer (modules/gcp/stages/bootstrap/plan_viewer.tf#L14)
- resource.google_organization_iam_member.guardrails (modules/gcp/stages/bootstrap/service_accounts.tf#L396)
- resource.google_organization_iam_member.guardrails_plan (modules/gcp/stages/bootstrap/service_accounts.tf#L422)
- resource.google_organization_iam_member.projects_delegated_folder_iam (modules/gcp/stages/bootstrap/service_accounts.tf#L271)
- resource.google_organization_iam_member.stage_org_roles (modules/gcp/stages/bootstrap/service_accounts.tf#L245)
- resource.google_organization_iam_member.stage_org_security_admin (modules/gcp/stages/bootstrap/service_accounts.tf#L257)
- resource.google_project_iam_member.stage_admin_project_roles (modules/gcp/stages/bootstrap/service_accounts.tf#L285)
- resource.google_service_account.guardrails (modules/gcp/stages/bootstrap/service_accounts.tf#L386)
- resource.google_service_account.guardrails_plan (modules/gcp/stages/bootstrap/service_accounts.tf#L413)
- resource.google_service_account.stage (modules/gcp/stages/bootstrap/service_accounts.tf#L234)
- resource.google_service_account_iam_member.guardrails_impersonation (modules/gcp/stages/bootstrap/service_accounts.tf#L404)
- resource.random_id.suffix (modules/gcp/stages/bootstrap/main.tf#L6)
- resource.terraform_data.guardrails_workspace_bound_by_id (modules/gcp/stages/bootstrap/service_accounts.tf#L435)
- resource.terraform_data.phase0_impersonation_is_time_boxed (modules/gcp/stages/bootstrap/main.tf#L77)
- resource.terraform_data.production_workspaces_bound_by_id (modules/gcp/stages/bootstrap/service_accounts.tf#L329)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | Email address for the organization administrator | `string` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing Account ID in format XXXXXX-XXXXXX-XXXXXX | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Numeric GCP Organization ID (digits only, without the 'organizations/' prefix). | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix prepended to all project names created by this bootstrap.<br/>Constraints: 1–10 characters, starts with a lowercase letter, may contain<br/>lowercase letters, digits, and hyphens. Kept short so the full project ID<br/>stays within GCP's 30-character limit after suffixes are appended. | `string` | n/a | yes |
| <a name="input_control_plane_workspaces"></a> [control\_plane\_workspaces](#input\_control\_plane\_workspaces) | TFC workspace name for each GCP control-plane stage. Keys are fixed: bootstrap, organization, projects, network-hub. Each workspace's plan phase is bound to <prefix>-<stage>-plan and its apply phase to <prefix>-<stage>-apply (bootstrap apply = the terraform-admin SA). | `map(string)` | <pre>{<br/>  "bootstrap": "gcp-bootstrap",<br/>  "network-hub": "gcp-network-hub",<br/>  "organization": "gcp-organization",<br/>  "projects": "gcp-projects"<br/>}</pre> | no |
| <a name="input_enable_github_wif"></a> [enable\_github\_wif](#input\_enable\_github\_wif) | Create the GitHub Actions WIF pool. Default false: no workflow in this repo uses GCP OIDC, so a standing trust is unused privilege. When true, the trust is pinned to github\_repository\_id + github\_repository\_owner\_id on refs/heads/main and bound ONLY to the read-only organization plan SA. | `bool` | `false` | no |
| <a name="input_enable_legacy_org_access_policy_grants"></a> [enable\_legacy\_org\_access\_policy\_grants](#input\_enable\_legacy\_org\_access\_policy\_grants) | LEGACY. Grant every workload apply SA roles/accesscontextmanager.policyEditor (plan: policyReader) on the org-wide policy vpc\_sc\_access\_policy\_id. Any one environment could then edit every perimeter in the org, including production and the hub. Default false: use enable\_scoped\_access\_policies instead. Enable only while migrating an existing deployment whose workload perimeters still live in the org-wide policy. | `bool` | `false` | no |
| <a name="input_enable_org_level_folder_iam_delegation"></a> [enable\_org\_level\_folder\_iam\_delegation](#input\_enable\_org\_level\_folder\_iam\_delegation) | LEGACY. Bind the projects-apply conditional roles/resourcemanager.folderIamAdmin at the ORG node, where it applies to every folder. Default false: gcp-organization binds it on each environment folder (workload roles only) and the shared folder (network roles only). Enable only to bridge a migration until gcp-organization has been re-applied. | `bool` | `false` | no |
| <a name="input_enable_pam"></a> [enable\_pam](#input\_enable\_pam) | Grant the organization stage SAs Privileged Access Manager rights at the org node (apply: roles/privilegedaccessmanager.admin, plan: viewer) so gcp-organization can manage the just-in-time org-admin entitlement. Keep it in step with the gcp-organization enable\_pam input. Default false. | `bool` | `false` | no |
| <a name="input_enable_phase0_admin_impersonation"></a> [enable\_phase0\_admin\_impersonation](#input\_enable\_phase0\_admin\_impersonation) | Let user:<admin\_email> impersonate the terraform-admin (gcp-bootstrap apply) SA. Needed for the documented phase-0 first apply, which runs as a human admin. Set false on pass 2, once gcp-bootstrap applies through TFC dynamic credentials, so no standing human path to the bootstrap apply identity remains. | `bool` | `true` | no |
| <a name="input_enable_plan_viewer_role"></a> [enable\_plan\_viewer\_role](#input\_enable\_plan\_viewer\_role) | Create the org custom role plan\_viewer\_role\_id (metadata-only get/list/getIamPolicy, no data access) and grant it to the plan identities: organization-plan on the admin project, and (through the gcp-projects folder grants) the workload and network plan SAs. Default true. Needs roles/iam.organizationRoleAdmin for the bootstrap apply identity (granted here). | `bool` | `true` | no |
| <a name="input_enable_principal_access_boundary"></a> [enable\_principal\_access\_boundary](#input\_enable\_principal\_access\_boundary) | Grant the organization stage SAs what the gcp-organization principal access boundary policy needs (apply: roles/iam.principalAccessBoundaryAdmin at the org and roles/resourcemanager.projectIamAdmin on the admin project for the policy binding; plan: roles/iam.principalAccessBoundaryViewer). Keep it in step with the gcp-organization enable\_principal\_access\_boundary input. Default false. | `bool` | `false` | no |
| <a name="input_enable_scoped_access_policies"></a> [enable\_scoped\_access\_policies](#input\_enable\_scoped\_access\_policies) | Default model for workload VPC-SC: gcp-organization creates one folder-scoped access policy per environment folder and grants that environment's SAs rights on it only. This grants the organization stage SAs what that needs (apply: roles/accesscontextmanager.policyAdmin, plan: policyReader at the org node). Keep it in step with the gcp-organization enable\_scoped\_access\_policies input. Default true. | `bool` | `true` | no |
| <a name="input_enable_tfc_oidc"></a> [enable\_tfc\_oidc](#input\_enable\_tfc\_oidc) | Enable Terraform Cloud OIDC for Dynamic Credentials | `bool` | `true` | no |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub organization (owner) name. Only used when enable\_github\_wif = true (the trust itself keys on github\_repository\_owner\_id, not this mutable name). | `string` | `null` | no |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository name (without owner prefix). Only used when enable\_github\_wif = true (the trust itself keys on github\_repository\_id, not this mutable name). | `string` | `null` | no |
| <a name="input_github_repository_id"></a> [github\_repository\_id](#input\_github\_repository\_id) | Immutable numeric GitHub repository ID (GET /repos/<owner>/<repo> -> .id). Required when enable\_github\_wif = true. | `string` | `null` | no |
| <a name="input_github_repository_owner_id"></a> [github\_repository\_owner\_id](#input\_github\_repository\_owner\_id) | Immutable numeric GitHub owner ID (GET /repos/<owner>/<repo> -> .owner.id). Required when enable\_github\_wif = true. | `string` | `null` | no |
| <a name="input_github_wif_pool_id"></a> [github\_wif\_pool\_id](#input\_github\_wif\_pool\_id) | Workload Identity Pool ID for the GitHub pool. Change it if you re-enable GitHub WIF within 30 days of the old pool being deleted (pool IDs are soft-deleted and not reusable for 30 days). | `string` | `"github-pool"` | no |
| <a name="input_guardrail_owner_members"></a> [guardrail\_owner\_members](#input\_guardrail\_owner\_members) | Break-glass principals allowed to impersonate the guardrails SA (roles/iam.serviceAccountTokenCreator) when guardrail\_owner\_mode = "separate"; routine changes go through the guardrails\_workspace. Use a group whose membership is granted just in time (PAM) and is disjoint from the people who can change the gcp-organization workspace. Empty = nobody can use the SA until set. | `list(string)` | `[]` | no |
| <a name="input_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#input\_guardrail\_owner\_mode) | Who owns IAM deny policies. "separate" (default): a dedicated <prefix>-guardrails-apply SA is the only automation identity with roles/iam.denyAdmin; the organization apply SA no longer holds it, so it cannot delete the containment deny policy that constrains it. "organization": legacy, the organization apply SA holds denyAdmin and gcp-organization manages the deny policies itself. Keep it in step with the gcp-organization guardrail\_owner\_mode input (it defaults to this stage's output). | `string` | `"separate"` | no |
| <a name="input_guardrails_workspace"></a> [guardrails\_workspace](#input\_guardrails\_workspace) | TFC workspace (envs/gcp/guardrails) that applies the org deny policies as the guardrails SA when guardrail\_owner\_mode = "separate". Its plan phase is bound to <prefix>-guardrails-plan and its apply phase to <prefix>-guardrails-apply, by the immutable ID in tfc\_workspace\_ids only (never by name); a production estate fails the plan without that ID. Null = no workspace identity, only the guardrail\_owner\_members break-glass path. | `string` | `"gcp-guardrails"` | no |
| <a name="input_network_folder_roles"></a> [network\_folder\_roles](#input\_network\_folder\_roles) | Roles the gcp-projects stage grants the network-hub plan/apply SAs on the `shared` folder (hub + DNS projects, hierarchical firewall policy, Shared VPC host). | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [<br/>    "roles/compute.networkAdmin",<br/>    "roles/compute.securityAdmin",<br/>    "roles/compute.xpnAdmin",<br/>    "roles/compute.orgFirewallPolicyAdmin",<br/>    "roles/compute.orgSecurityResourceAdmin",<br/>    "roles/dns.admin",<br/>    "roles/servicenetworking.networksAdmin",<br/>    "roles/serviceusage.serviceUsageAdmin"<br/>  ],<br/>  "plan": [<br/>    "roles/compute.viewer",<br/>    "roles/dns.reader",<br/>    "roles/serviceusage.serviceUsageViewer"<br/>  ]<br/>}</pre> | no |
| <a name="input_phase0_admin_impersonation_expires_at"></a> [phase0\_admin\_impersonation\_expires\_at](#input\_phase0\_admin\_impersonation\_expires\_at) | RFC 3339 UTC timestamp after which the phase-0 admin\_email -> terraform-admin impersonation grant stops working (IAM condition). Set it to the end of the bootstrap window. Null = no expiry (a check warns on production estates). | `string` | `null` | no |
| <a name="input_plan_viewer_permissions"></a> [plan\_viewer\_permissions](#input\_plan\_viewer\_permissions) | Permissions of the plan viewer custom role. Metadata-only by design: it fills the gaps left by the predefined metadata viewers in the plan role lists (bucket and repository metadata, logging and monitoring configuration). Data-plane permissions (object reads, table data, secret payloads, decrypt, log entries, token minting) are rejected. | `list(string)` | <pre>[<br/>  "artifactregistry.repositories.get",<br/>  "artifactregistry.repositories.getIamPolicy",<br/>  "artifactregistry.repositories.list",<br/>  "iam.roles.get",<br/>  "iam.roles.list",<br/>  "logging.buckets.get",<br/>  "logging.buckets.list",<br/>  "logging.exclusions.get",<br/>  "logging.exclusions.list",<br/>  "logging.logMetrics.get",<br/>  "logging.logMetrics.list",<br/>  "logging.sinks.get",<br/>  "logging.sinks.list",<br/>  "logging.views.get",<br/>  "logging.views.list",<br/>  "monitoring.alertPolicies.get",<br/>  "monitoring.alertPolicies.list",<br/>  "monitoring.dashboards.get",<br/>  "monitoring.dashboards.list",<br/>  "monitoring.notificationChannels.get",<br/>  "monitoring.notificationChannels.list",<br/>  "resourcemanager.folders.get",<br/>  "resourcemanager.projects.get",<br/>  "resourcemanager.tagKeys.get",<br/>  "resourcemanager.tagValues.get",<br/>  "storage.buckets.get",<br/>  "storage.buckets.getIamPolicy",<br/>  "storage.buckets.list",<br/>  "storage.buckets.listEffectiveTags",<br/>  "storage.buckets.listTagBindings"<br/>]</pre> | no |
| <a name="input_plan_viewer_role_id"></a> [plan\_viewer\_role\_id](#input\_plan\_viewer\_role\_id) | role\_id of the org-level plan viewer custom role. A deleted custom role ID is unusable for 37 days, so change it if you recreate the role within that window. | `string` | `"landingZonePlanViewer"` | no |
| <a name="input_production_workload_environments"></a> [production\_workload\_environments](#input\_production\_workload\_environments) | Subset of workload\_environments that are production (the environments map entries with is\_production = true). A check warns when any of their workspaces, or any control-plane workspace, is still WIF-bound by mutable NAME instead of an immutable tfc\_workspace\_ids entry. | `set(string)` | `[]` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | HCP Terraform / Terraform Enterprise hostname issuing the dynamic-credential tokens the TFC WIF pool trusts (app.terraform.io, app.eu.terraform.io or a TFE host). | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization name. Required (non-null) when enable\_tfc\_oidc = true — leaving it null while enable\_tfc\_oidc = true silently skips pool creation with no error. | `string` | `null` | no |
| <a name="input_tfc_organization_id"></a> [tfc\_organization\_id](#input\_tfc\_organization\_id) | Optional immutable TFC organization ID (org-xxxxxxxx). When set, the WIF provider condition also pins it, so a renamed/re-registered organization name cannot satisfy the trust. | `string` | `null` | no |
| <a name="input_tfc_project_ids"></a> [tfc\_project\_ids](#input\_tfc\_project\_ids) | Optional allow-list of TFC project IDs (prj-xxxxxxxx) the GCP workspaces live in. When non-empty, the WIF provider condition rejects tokens from workspaces in any other TFC project (blocks workspace-name squatting elsewhere in the org). | `list(string)` | `[]` | no |
| <a name="input_tfc_workload_workspace_prefix"></a> [tfc\_workload\_workspace\_prefix](#input\_tfc\_workload\_workspace\_prefix) | TFC workspace name prefix for per-environment workload workspaces (workspace = <prefix><env>). | `string` | `"gcp-workload-"` | no |
| <a name="input_tfc_workspace_ids"></a> [tfc\_workspace\_ids](#input\_tfc\_workspace\_ids) | Optional map of TFC workspace NAME -> immutable workspace ID (ws-xxxxxxxx). When a workspace has an entry, its WIF bindings match the immutable ID (attribute.workspace\_id\_phase) instead of the name, so deleting/recreating or squatting the name gains nothing. Expected for every control-plane workspace and every production workload workspace (see production\_workload\_environments). | `map(string)` | `{}` | no |
| <a name="input_vpc_sc_access_policy_id"></a> [vpc\_sc\_access\_policy\_id](#input\_vpc\_sc\_access\_policy\_id) | Optional numeric ID of the org-wide Access Context Manager policy. Only used with enable\_legacy\_org\_access\_policy\_grants = true. The default model gives each environment its own folder-scoped access policy (created by gcp-organization), so a workload SA can never edit another environment's or the hub's perimeter. | `string` | `null` | no |
| <a name="input_workload_billing_roles"></a> [workload\_billing\_roles](#input\_workload\_billing\_roles) | Billing-account roles for each workload SA (budgets live on the billing account, not a folder). Not org-level. | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [<br/>    "roles/billing.costsManager",<br/>    "roles/billing.user"<br/>  ],<br/>  "plan": [<br/>    "roles/billing.viewer"<br/>  ]<br/>}</pre> | no |
| <a name="input_workload_environments"></a> [workload\_environments](#input\_workload\_environments) | Application environment keys. Each gets a <prefix>-wl-<env>-plan / -apply SA pair, bound to TFC workspace <tfc\_workload\_workspace\_prefix><env>. These SAs get NO org-level role; their folder roles are granted by the gcp-projects stage. | `set(string)` | `[]` | no |
| <a name="input_workload_folder_roles"></a> [workload\_folder\_roles](#input\_workload\_folder\_roles) | Roles the gcp-projects stage grants each workload plan/apply SA on its OWN environment folder. Also the allow-list (with network\_folder\_roles) for the projects-apply SA's delegated folder-IAM grant. Avoid roles/owner: anything listed here becomes grantable on ANY folder by projects-apply. | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [<br/>    "roles/resourcemanager.projectIamAdmin",<br/>    "roles/iam.serviceAccountAdmin",<br/>    "roles/iam.serviceAccountUser",<br/>    "roles/serviceusage.serviceUsageAdmin",<br/>    "roles/compute.admin",<br/>    "roles/compute.xpnAdmin",<br/>    "roles/servicenetworking.networksAdmin",<br/>    "roles/dns.admin",<br/>    "roles/secretmanager.admin",<br/>    "roles/storage.admin",<br/>    "roles/cloudkms.admin",<br/>    "roles/bigquery.admin",<br/>    "roles/logging.admin",<br/>    "roles/monitoring.admin",<br/>    "roles/pubsub.admin",<br/>    "roles/run.admin",<br/>    "roles/artifactregistry.admin",<br/>    "roles/resourcemanager.projectCreator",<br/>    "roles/iam.workloadIdentityPoolAdmin",<br/>    "roles/cloudsql.admin",<br/>    "roles/container.admin",<br/>    "roles/osconfig.patchDeploymentAdmin"<br/>  ],<br/>  "plan": [<br/>    "roles/resourcemanager.folderViewer",<br/>    "roles/iam.securityReviewer",<br/>    "roles/iam.serviceAccountViewer",<br/>    "roles/iam.workloadIdentityPoolViewer",<br/>    "roles/serviceusage.serviceUsageViewer",<br/>    "roles/compute.viewer",<br/>    "roles/dns.reader",<br/>    "roles/cloudkms.viewer",<br/>    "roles/secretmanager.viewer",<br/>    "roles/pubsub.viewer",<br/>    "roles/bigquery.metadataViewer",<br/>    "roles/cloudsql.viewer",<br/>    "roles/run.viewer",<br/>    "roles/container.clusterViewer",<br/>    "roles/monitoring.viewer",<br/>    "roles/osconfig.patchDeploymentViewer"<br/>  ]<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_project_id"></a> [admin\_project\_id](#output\_admin\_project\_id) | Project ID of the admin project |
| <a name="output_admin_project_number"></a> [admin\_project\_number](#output\_admin\_project\_number) | Project Number of the admin project |
| <a name="output_delegated_network_folder_roles"></a> [delegated\_network\_folder\_roles](#output\_delegated\_network\_folder\_roles) | Roles projects-apply may grant on the SHARED (network) folder. gcp-organization binds the conditional folderIamAdmin on the shared folder with this allow-list. |
| <a name="output_delegated_workload_folder_roles"></a> [delegated\_workload\_folder\_roles](#output\_delegated\_workload\_folder\_roles) | Roles projects-apply may grant on each ENVIRONMENT folder. gcp-organization binds the conditional folderIamAdmin on every environment folder with this allow-list. |
| <a name="output_github_oidc_pool_id"></a> [github\_oidc\_pool\_id](#output\_github\_oidc\_pool\_id) | Workload Identity Pool ID for GitHub Actions OIDC (null unless enable\_github\_wif = true) |
| <a name="output_github_oidc_pool_name"></a> [github\_oidc\_pool\_name](#output\_github\_oidc\_pool\_name) | Fully-qualified Workload Identity Pool name for GitHub Actions OIDC (null unless enable\_github\_wif = true) |
| <a name="output_github_oidc_provider_name"></a> [github\_oidc\_provider\_name](#output\_github\_oidc\_provider\_name) | Fully-qualified Workload Identity Provider name for GitHub Actions (null unless enable\_github\_wif = true) |
| <a name="output_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#output\_guardrail\_owner\_mode) | Deny-policy ownership mode ("separate" or "organization"); gcp-organization defaults its own guardrail\_owner\_mode to this. |
| <a name="output_guardrails_plan_service_account"></a> [guardrails\_plan\_service\_account](#output\_guardrails\_plan\_service\_account) | Email of the read-only plan SA of the gcp-guardrails workspace, or null when guardrail\_owner\_mode = "organization" or guardrails\_workspace = null. |
| <a name="output_guardrails_service_account"></a> [guardrails\_service\_account](#output\_guardrails\_service\_account) | Email of the guardrails SA (sole automation holder of roles/iam.denyAdmin), or null when guardrail\_owner\_mode = "organization". |
| <a name="output_guardrails_workspace_bound_by_id"></a> [guardrails\_workspace\_bound\_by\_id](#output\_guardrails\_workspace\_bound\_by\_id) | Whether the gcp-guardrails workspace is WIF-bound (by immutable workspace ID; it is never bound by name). |
| <a name="output_network_folder_roles"></a> [network\_folder\_roles](#output\_network\_folder\_roles) | Effective folder roles for the network-hub SAs on the shared folder ({ plan, apply }, plan includes the plan viewer custom role); consumed by gcp-projects. |
| <a name="output_org_role_grants"></a> [org\_role\_grants](#output\_org\_role\_grants) | Audit view of every ORG-level role granted by this stage, keyed by identity (<stage>-<phase>). Workload identities never appear here. |
| <a name="output_phase0_admin_impersonation_members"></a> [phase0\_admin\_impersonation\_members](#output\_phase0\_admin\_impersonation\_members) | Human principals that may impersonate the terraform-admin SA (empty once enable\_phase0\_admin\_impersonation = false). |
| <a name="output_plan_viewer_role"></a> [plan\_viewer\_role](#output\_plan\_viewer\_role) | Full name (organizations/<org>/roles/<id>) of the metadata-only plan viewer custom role, or null when enable\_plan\_viewer\_role = false. |
| <a name="output_production_workspaces_bound_by_name"></a> [production\_workspaces\_bound\_by\_name](#output\_production\_workspaces\_bound\_by\_name) | Control-plane and production workload workspaces still WIF-bound by mutable name (empty when production\_workload\_environments is empty or every one has a tfc\_workspace\_ids entry). |
| <a name="output_resman_email"></a> [resman\_email](#output\_resman\_email) | DEPRECATED (superseded by stage\_service\_accounts). Email of the organization-stage APPLY SA, which now holds the privileged org roles the old opt-in resman SA held. |
| <a name="output_stage_service_accounts"></a> [stage\_service\_accounts](#output\_stage\_service\_accounts) | Map of control-plane stage (bootstrap, organization, projects, network-hub) -> { plan, apply } SA emails. |
| <a name="output_suffix"></a> [suffix](#output\_suffix) | Random suffix used for uniqueness |
| <a name="output_terraform_admin_email"></a> [terraform\_admin\_email](#output\_terraform\_admin\_email) | Email of the Terraform Admin Service Account |
| <a name="output_tfc_apply_service_accounts"></a> [tfc\_apply\_service\_accounts](#output\_tfc\_apply\_service\_accounts) | Map of TFC workspace name -> APPLY-phase SA email (set as TFC\_GCP\_APPLY\_SERVICE\_ACCOUNT\_EMAIL on that workspace). |
| <a name="output_tfc_attribute_condition"></a> [tfc\_attribute\_condition](#output\_tfc\_attribute\_condition) | The CEL attribute\_condition on the TFC WIF provider (null if TFC OIDC not enabled). |
| <a name="output_tfc_oidc_pool_id"></a> [tfc\_oidc\_pool\_id](#output\_tfc\_oidc\_pool\_id) | Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not enabled) |
| <a name="output_tfc_oidc_pool_name"></a> [tfc\_oidc\_pool\_name](#output\_tfc\_oidc\_pool\_name) | Fully-qualified Workload Identity Pool name for Terraform Cloud OIDC (null if TFC OIDC not enabled) |
| <a name="output_tfc_oidc_provider_name"></a> [tfc\_oidc\_provider\_name](#output\_tfc\_oidc\_provider\_name) | Fully-qualified Workload Identity Provider name for Terraform Cloud OIDC (null if TFC OIDC not enabled) |
| <a name="output_tfc_plan_service_accounts"></a> [tfc\_plan\_service\_accounts](#output\_tfc\_plan\_service\_accounts) | Map of TFC workspace name -> PLAN-phase SA email (set as TFC\_GCP\_PLAN\_SERVICE\_ACCOUNT\_EMAIL on that workspace). |
| <a name="output_tfc_workload_provider_name"></a> [tfc\_workload\_provider\_name](#output\_tfc\_workload\_provider\_name) | Full WIF provider resource name (projects/<number>/locations/global/workloadIdentityPools/tfc-pool/providers/terraform-cloud) for the TFC\_GCP\_WORKLOAD\_PROVIDER\_NAME workspace variable. Null if TFC OIDC not enabled. |
| <a name="output_workload_folder_roles"></a> [workload\_folder\_roles](#output\_workload\_folder\_roles) | Effective folder roles for workload SAs ({ plan, apply }, plan includes the plan viewer custom role); consumed by gcp-projects so the grant list and the projects-apply delegation condition stay in lock-step. |
| <a name="output_workload_service_accounts"></a> [workload\_service\_accounts](#output\_workload\_service\_accounts) | Map of application environment key -> { plan, apply } SA emails. Consumed by gcp-projects, which grants them roles on the environment folder. |
<!-- END_TF_DOCS -->
