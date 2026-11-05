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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules


- gh_oidc - ../../iam/workload-identity
- terraform_admin_sa - ../../iam/service-account
- tfc_oidc - ../../iam/workload-identity


## Resources

The following resources are created:


- resource.google_access_context_manager_access_policy_iam_member.workload (modules/gcp/stages/bootstrap/service_accounts.tf#L256)
- resource.google_billing_account_iam_member.stage_billing_roles (modules/gcp/stages/bootstrap/service_accounts.tf#L245)
- resource.google_organization_iam_member.projects_delegated_folder_iam (modules/gcp/stages/bootstrap/service_accounts.tf#L225)
- resource.google_organization_iam_member.stage_org_roles (modules/gcp/stages/bootstrap/service_accounts.tf#L201)
- resource.google_organization_iam_member.stage_org_security_admin (modules/gcp/stages/bootstrap/service_accounts.tf#L213)
- resource.google_project.admin_project (modules/gcp/stages/bootstrap/main.tf#L2)
- resource.google_project_iam_member.stage_admin_project_roles (modules/gcp/stages/bootstrap/service_accounts.tf#L237)
- resource.google_project_service.admin_project_services (modules/gcp/stages/bootstrap/main.tf#L23)
- resource.google_service_account.stage (modules/gcp/stages/bootstrap/service_accounts.tf#L190)
- resource.random_id.suffix (modules/gcp/stages/bootstrap/main.tf#L18)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | Email address for the organization administrator | `string` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing Account ID in format XXXXXX-XXXXXX-XXXXXX | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Numeric GCP Organization ID (digits only, without the 'organizations/' prefix). | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix prepended to all project names created by this bootstrap.<br/>Constraints: 1–10 characters, starts with a lowercase letter, may contain<br/>lowercase letters, digits, and hyphens. Kept short so the full project ID<br/>stays within GCP's 30-character limit after suffixes are appended. | `string` | n/a | yes |
| <a name="input_control_plane_workspaces"></a> [control\_plane\_workspaces](#input\_control\_plane\_workspaces) | TFC workspace name for each GCP control-plane stage. Keys are fixed: bootstrap, organization, projects, network-hub. Each workspace's plan phase is bound to <prefix>-<stage>-plan and its apply phase to <prefix>-<stage>-apply (bootstrap apply = the terraform-admin SA). | `map(string)` | <pre>{<br/>  "bootstrap": "gcp-bootstrap",<br/>  "network-hub": "gcp-network-hub",<br/>  "organization": "gcp-organization",<br/>  "projects": "gcp-projects"<br/>}</pre> | no |
| <a name="input_enable_github_wif"></a> [enable\_github\_wif](#input\_enable\_github\_wif) | Create the GitHub Actions WIF pool. Default false: no workflow in this repo uses GCP OIDC, so a standing trust is unused privilege (audit C2). When true, the trust is pinned to github\_repository\_id + github\_repository\_owner\_id on refs/heads/main and bound ONLY to the read-only organization plan SA. | `bool` | `false` | no |
| <a name="input_enable_tfc_oidc"></a> [enable\_tfc\_oidc](#input\_enable\_tfc\_oidc) | Enable Terraform Cloud OIDC for Dynamic Credentials | `bool` | `true` | no |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub organization (owner) name. Only used when enable\_github\_wif = true (the trust itself keys on github\_repository\_owner\_id, not this mutable name). | `string` | `null` | no |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository name (without owner prefix). Only used when enable\_github\_wif = true (the trust itself keys on github\_repository\_id, not this mutable name). | `string` | `null` | no |
| <a name="input_github_repository_id"></a> [github\_repository\_id](#input\_github\_repository\_id) | Immutable numeric GitHub repository ID (GET /repos/<owner>/<repo> -> .id). Required when enable\_github\_wif = true. | `string` | `null` | no |
| <a name="input_github_repository_owner_id"></a> [github\_repository\_owner\_id](#input\_github\_repository\_owner\_id) | Immutable numeric GitHub owner ID (GET /repos/<owner>/<repo> -> .owner.id). Required when enable\_github\_wif = true. | `string` | `null` | no |
| <a name="input_github_wif_pool_id"></a> [github\_wif\_pool\_id](#input\_github\_wif\_pool\_id) | Workload Identity Pool ID for the GitHub pool. Change it if you re-enable GitHub WIF within 30 days of the old pool being deleted (pool IDs are soft-deleted and not reusable for 30 days). | `string` | `"github-pool"` | no |
| <a name="input_network_folder_roles"></a> [network\_folder\_roles](#input\_network\_folder\_roles) | Roles the gcp-projects stage grants the network-hub plan/apply SAs on the `shared` folder (hub + DNS projects, hierarchical firewall policy, Shared VPC host). | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [<br/>    "roles/compute.networkAdmin",<br/>    "roles/compute.securityAdmin",<br/>    "roles/compute.xpnAdmin",<br/>    "roles/compute.orgFirewallPolicyAdmin",<br/>    "roles/compute.orgSecurityResourceAdmin",<br/>    "roles/dns.admin",<br/>    "roles/servicenetworking.networksAdmin",<br/>    "roles/serviceusage.serviceUsageAdmin"<br/>  ],<br/>  "plan": [<br/>    "roles/compute.viewer",<br/>    "roles/dns.reader",<br/>    "roles/serviceusage.serviceUsageViewer"<br/>  ]<br/>}</pre> | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization name. Required (non-null) when enable\_tfc\_oidc = true — leaving it null while enable\_tfc\_oidc = true silently skips pool creation with no error. | `string` | `null` | no |
| <a name="input_tfc_organization_id"></a> [tfc\_organization\_id](#input\_tfc\_organization\_id) | Optional immutable TFC organization ID (org-xxxxxxxx). When set, the WIF provider condition also pins it, so a renamed/re-registered organization name cannot satisfy the trust. | `string` | `null` | no |
| <a name="input_tfc_project_ids"></a> [tfc\_project\_ids](#input\_tfc\_project\_ids) | Optional allow-list of TFC project IDs (prj-xxxxxxxx) the GCP workspaces live in. When non-empty, the WIF provider condition rejects tokens from workspaces in any other TFC project (blocks workspace-name squatting elsewhere in the org). | `list(string)` | `[]` | no |
| <a name="input_tfc_workload_workspace_prefix"></a> [tfc\_workload\_workspace\_prefix](#input\_tfc\_workload\_workspace\_prefix) | TFC workspace name prefix for per-environment workload workspaces (workspace = <prefix><env>). | `string` | `"gcp-workload-"` | no |
| <a name="input_tfc_workspace_ids"></a> [tfc\_workspace\_ids](#input\_tfc\_workspace\_ids) | Optional map of TFC workspace NAME -> immutable workspace ID (ws-xxxxxxxx). When a workspace has an entry, its WIF bindings match the immutable ID (attribute.workspace\_id\_phase) instead of the name, so deleting/recreating or squatting the name gains nothing. | `map(string)` | `{}` | no |
| <a name="input_vpc_sc_access_policy_id"></a> [vpc\_sc\_access\_policy\_id](#input\_vpc\_sc\_access\_policy\_id) | Optional numeric Access Context Manager policy ID. When set, workload apply SAs get roles/accesscontextmanager.policyEditor (plan: policyReader) on THIS policy only, so gcp-workload-<env> can manage its own perimeter without an org-level role. | `string` | `null` | no |
| <a name="input_workload_billing_roles"></a> [workload\_billing\_roles](#input\_workload\_billing\_roles) | Billing-account roles for each workload SA (budgets live on the billing account, not a folder). Not org-level. | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [<br/>    "roles/billing.costsManager"<br/>  ],<br/>  "plan": [<br/>    "roles/billing.viewer"<br/>  ]<br/>}</pre> | no |
| <a name="input_workload_environments"></a> [workload\_environments](#input\_workload\_environments) | Application environment keys. Each gets a <prefix>-wl-<env>-plan / -apply SA pair, bound to TFC workspace <tfc\_workload\_workspace\_prefix><env>. These SAs get NO org-level role; their folder roles are granted by the gcp-projects stage. | `set(string)` | `[]` | no |
| <a name="input_workload_folder_roles"></a> [workload\_folder\_roles](#input\_workload\_folder\_roles) | Roles the gcp-projects stage grants each workload plan/apply SA on its OWN environment folder. Also the allow-list (with network\_folder\_roles) for the projects-apply SA's delegated folder-IAM grant. Avoid roles/owner: anything listed here becomes grantable on ANY folder by projects-apply. | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [<br/>    "roles/resourcemanager.projectIamAdmin",<br/>    "roles/iam.serviceAccountAdmin",<br/>    "roles/iam.serviceAccountUser",<br/>    "roles/serviceusage.serviceUsageAdmin",<br/>    "roles/compute.admin",<br/>    "roles/compute.xpnAdmin",<br/>    "roles/servicenetworking.networksAdmin",<br/>    "roles/dns.admin",<br/>    "roles/secretmanager.admin",<br/>    "roles/storage.admin",<br/>    "roles/cloudkms.admin",<br/>    "roles/bigquery.admin",<br/>    "roles/logging.admin",<br/>    "roles/monitoring.admin",<br/>    "roles/pubsub.admin",<br/>    "roles/run.admin",<br/>    "roles/artifactregistry.admin"<br/>  ],<br/>  "plan": [<br/>    "roles/viewer",<br/>    "roles/iam.securityReviewer",<br/>    "roles/resourcemanager.folderViewer"<br/>  ]<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_project_id"></a> [admin\_project\_id](#output\_admin\_project\_id) | Project ID of the admin project |
| <a name="output_admin_project_number"></a> [admin\_project\_number](#output\_admin\_project\_number) | Project Number of the admin project |
| <a name="output_github_oidc_pool_id"></a> [github\_oidc\_pool\_id](#output\_github\_oidc\_pool\_id) | Workload Identity Pool ID for GitHub Actions OIDC (null unless enable\_github\_wif = true) |
| <a name="output_github_oidc_pool_name"></a> [github\_oidc\_pool\_name](#output\_github\_oidc\_pool\_name) | Fully-qualified Workload Identity Pool name for GitHub Actions OIDC (null unless enable\_github\_wif = true) |
| <a name="output_github_oidc_provider_name"></a> [github\_oidc\_provider\_name](#output\_github\_oidc\_provider\_name) | Fully-qualified Workload Identity Provider name for GitHub Actions (null unless enable\_github\_wif = true) |
| <a name="output_network_folder_roles"></a> [network\_folder\_roles](#output\_network\_folder\_roles) | Folder roles for the network-hub SAs on the shared folder ({ plan, apply }); consumed by gcp-projects. |
| <a name="output_org_role_grants"></a> [org\_role\_grants](#output\_org\_role\_grants) | Audit view of every ORG-level role granted by this stage, keyed by identity (<stage>-<phase>). Workload identities never appear here (C2). |
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
| <a name="output_workload_folder_roles"></a> [workload\_folder\_roles](#output\_workload\_folder\_roles) | Folder roles for workload SAs ({ plan, apply }); consumed by gcp-projects so the grant list and the projects-apply delegation condition stay in lock-step. |
| <a name="output_workload_service_accounts"></a> [workload\_service\_accounts](#output\_workload\_service\_accounts) | Map of application environment key -> { plan, apply } SA emails. Consumed by gcp-projects, which grants them roles on the environment folder. |
<!-- END_TF_DOCS -->
