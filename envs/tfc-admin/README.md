# tfc-admin

Declares the whole Terraform Cloud / HCP Terraform layer as code (audit C3): every
deployable root's workspace plus the native TFC controls around it. It declares NO
cloud provider, so it needs no cloud credentials, only a TFC token (`TFE_TOKEN`).
Create its own `tfc-admin` workspace by hand once, then it manages all the others
and adopts itself via an import block (`manage_tfc_admin_workspace`, default true). Only
a managed tfc-admin workspace gets `speculative_enabled = false`. An unmanaged one keeps
TFC's default, so any PR's plan could read its org-admin `TFE_TOKEN`; a `check` warns
when it is unmanaged and VCS-connected.

## Configuration: `config/landing-zone.yaml`

tfc-admin reads the committed single-source config (`landing_zone_config_path`, default
`../../config/landing-zone.yaml`; `""` disables it). Precedence: explicit variable > config file >
built-in default.

| Input | Config key |
|-------|------------|
| `tfc_organization` | `org.tfc.organization` |
| `enable_gcp` / `enable_aws` / `enable_saas` | `gcp.enabled` / `aws.enabled` / `saas.enabled` |
| `gcp-workload-<env>` workspaces | keys of `gcp.environments` |
| `aws-workload-<env>` workspaces + their `workload_account_key` | `aws.workload_environments[<env>].account_key` |
| `saas_workspaces` | `saas.workspaces` |
| Project names | `org.tfc.project_name_prefix` (`<prefix><cloud>`), or `org.tfc.gcp_project` / `aws_project` / `saas_project` / `platform_project` / `guardrails_project` (+ `gcp_workloads_project` / `aws_workloads_project` when split) |
| `split_workload_projects` | `org.tfc.split_workload_projects` |
| Production workloads (no speculative plans) | `gcp.environments[<env>].is_production` / `aws.workload_environments[<env>].is_production` (unset: keys `prod` / `production`) |
| `vcs_repo` | `org.tfc.vcs_repo` (IDs only, no secrets) |

An explicit `environments` variable replaces both derived environment lists, as before. Per-workspace
values from `config/tfc-workspaces.yaml` and `workspace_variables` still override the derived ones.
`org.tfc.aws_project` is also read by `aws-organization` (`tfc_project`), so the member-account OIDC
trust and the workspace project cannot drift apart.

**Provider and tier.** The `tfe` provider is pinned `>= 0.83.0, < 1.0.0`. Health assessments
(`enable_health_assessments`, default on) and policy sets (`enable_policy_sets`) need a **paid HCP
Terraform tier**; on the free tier, set `enable_health_assessments = false` and leave policy sets off.

## What it manages

| Control | How |
|---------|-----|
| Cloud selection | `enable_gcp`, `enable_aws`, `enable_saas` + `saas_workspaces` (or `<cloud>.enabled` / `saas.workspaces` in `config/landing-zone.yaml`), all default **false**; at least one must be true (validation). Each estate gets only the workspaces of the clouds it enables. |
| Execution mode | `execution_mode` (remote/agent) for every workspace, overridden per workspace by `workspace_execution_modes`. Default `{ gcp-bootstrap = "local" }`: the GCP phase-0 apply runs on the operator's machine with ADC while TFC stores state. Set `{}` after the second bootstrap pass. `local` is accepted only for `gcp-bootstrap` / `aws-organization`. |
| Projects + team access | One `tfe_project` per cloud in use (`<prefix>gcp/aws/saas/platform`; `split_workload_projects` adds `<prefix>gcp-workloads` / `<prefix>aws-workloads`). Least privilege: on a project holding control-plane workspaces, `platform_team_id` gets only **custom** access (`runs = platform_team_control_plane_runs`, default `plan`; variables and state read-only; no locking, workspace create/delete/move, run tasks or policy overrides), and `control_plane_approvers_team_id` (a small, separate team) gets custom `runs = apply` with variables read-only, so the person who changes control-plane code or inputs cannot also confirm the apply. Workload-only projects give the platform team fixed **write**; workload workspaces sharing a project with the control plane get write through a workspace-level `tfe_team_access`. `viewer_team_ids` get **read** on every project. With AWS, enable the split only after the workload accounts' OIDC trust names the workloads project (`aws-organization` `tfc_workspace_bindings[*].project`). **Guardrails:** `gcp-guardrails` (org IAM deny policies) always gets its own `<prefix>guardrails` project (`org.tfc.guardrails_project` overrides the name) where only `security_team_id` has access (custom: `runs = apply`, variables/state read-only); no platform, approvers or viewer grant, and a `check` warns while `security_team_id` is null. |
| Trigger patterns | Each VCS workspace triggers on `<working_dir>/**` plus the module domains its root consumes (`modules/gcp/**`, `modules/aws/**`, `modules/{saas,supabase,vercel}/**`, `modules/tfc/**`), so a module-only PR triggers plans. |
| Speculative plans | Off (`speculative_enabled = false`) for `speculative_disabled_workspaces` (the control plane + `tfc-admin`), always for `gcp-guardrails` and, with `disable_speculative_on_production` (default true), for every production workload workspace, and, with `disable_speculative_on_saas` (default true), for every `saas-<name>` workspace (static account-wide Supabase/Vercel tokens, no plan identity). So a PR's code never runs with a privileged, production or SaaS-account credential. Control-plane workspaces also disallow UI destroy plans. `auto_apply` stays false everywhere. |
| Remote state | `global_remote_state = false` everywhere; `remote_state_consumer_ids` encode the real read graph from `envs/**` `terraform_remote_state` blocks. Opt-in cross-cloud edges (saas secret bridge, cross-cloud references) via `extra_remote_state_consumers`. |
| Health assessments | `enable_health_assessments` (default true): native drift detection + continuous validation. |
| Dynamic credentials | Per-workspace `TFC_GCP_*` / `TFC_AWS_*` env vars, set only when their inputs are supplied (see below). The multi-account roots `aws-security` / `aws-backup` get the management role (`aws_management_plan_role_arn` / `aws_management_apply_role_arn`) as their default configuration plus a `TFC_AWS_PROVIDER_AUTH_<alias>` / `TFC_AWS_PLAN_ROLE_ARN_<alias>` / `TFC_AWS_APPLY_ROLE_ARN_<alias>` set per member-account alias (`security_tooling`, `log_archive`, `forensics`; `backup`), derived from aws-organization `tfc_*_role_arns` or `aws_alias_role_arns`. They get nothing until every alias has roles. `aws-organization` gets the management role. |
| Variables | Org-wide values in the `<prefix>common` variable set (attached to every workspace). Per-workspace values come from a committed `config/tfc-workspaces.yaml` (`workspace_variables_file`, read only if present; no secrets; see `config/tfc-workspaces.example.yaml`) and `workspace_variables` (wins). `gcp-workload-<env>` / `aws-workload-<env>` get `environment` derived from the name; `aws-workload-<env>` also gets `workload_account_key` from `aws.workload_environments[<env>].account_key` (or `environments[<env>].aws_account_key`). |
| Policy | Optional OPA policy set from `policies/opa/` (`enable_policy_sets`, default false). The policies are **mixed mandatory/advisory**: 10 mandatory and 4 advisory, per `policies/opa/policies.hcl`. Mandatory failures are **not overridable** (`policy_set_overridable`, default false), and `opa_version` is pinned so that an OPA release cannot change results unreviewed. Paid tier only. |

## Variables belong in code

Control-plane inputs (for example `enable_admin_containment`, `containment_exempt_principals`,
`break_glass_trusted_principals`) must come from `config/landing-zone.yaml`,
`config/tfc-workspaces.yaml` or `workspace_variables`, all reviewed in a PR. TFC cannot forbid
an organization owner from setting a variable in the UI, so this is enforced by permissions, not
by Terraform: no team this root grants has `variables = write` on a control-plane project, and
tfc-admin reverts any drift on the variables it manages at its next apply. Review the workspace
variables in health assessments and audit-trail events for UI edits by owners.

## Two-pass bootstrap (dynamic credentials)

The plan/apply identities are created by roots whose workspaces this root creates:

1. Apply tfc-admin: workspaces exist, no credential env vars yet.
2. Apply `gcp-bootstrap` (phase-0) and/or `aws-organization`.
3. Feed their outputs back, either by copying them into
   `gcp_workload_provider_name`, `gcp_plan_service_accounts`, `gcp_apply_service_accounts`,
   `aws_plan_role_arns`, `aws_apply_role_arns` (maps keyed by workspace name), or by
   setting `gcp_bootstrap_outputs_from_tfc` / `aws_organization_outputs_from_tfc = true`
   (read via `tfe_outputs`; AWS maps each single-account workspace => account key from
   aws-organization `tfc_workspace_bindings`, `environments[<env>].aws_account_key` or
   `aws_workspace_account_keys`). tfc-admin is then added as a remote-state consumer of those producers.
4. Re-apply tfc-admin, with `workspace_execution_modes = {}` so `gcp-bootstrap` moves to
   remote execution.

See [docs/runbooks/bootstrap.md](../../docs/runbooks/bootstrap.md) and
[docs/guides/CI_SECRETS.md](../../docs/guides/CI_SECRETS.md).

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
