# tfc-admin

Declares the whole Terraform Cloud / HCP Terraform layer as code (audit C3): every
deployable root's workspace plus the native TFC controls around it. It declares NO
cloud provider, so it needs no cloud credentials, only a TFC token (`TFE_TOKEN`).
Create its own `tfc-admin` workspace by hand once, then it manages all the others
(and, with `manage_tfc_admin_workspace = true`, adopts itself via an import block).

## What it manages

| Control | How |
|---------|-----|
| Cloud selection | `enable_gcp` (default true), `enable_aws` (default false), `enable_saas` + `saas_workspaces`. An AWS-only or SaaS-only estate gets no `gcp-*` workspaces. |
| Projects + team access | One `tfe_project` per cloud in use (`<prefix>gcp/aws/saas/platform`); `platform_team_id` gets **write**, `viewer_team_ids` get **read** on every project. |
| Trigger patterns | Each VCS workspace triggers on `<working_dir>/**` plus the module domains its root consumes (`modules/gcp/**`, `modules/aws/**`, `modules/{saas,supabase,vercel}/**`, `modules/tfc/**`), so a module-only PR triggers plans. |
| Speculative plans | Off (`speculative_enabled = false`) for `speculative_disabled_workspaces` (the control plane + `tfc-admin`), so a PR cannot obtain a plan with privileged credentials. Control-plane workspaces also disallow UI destroy plans. |
| Remote state | `global_remote_state = false` everywhere; `remote_state_consumer_ids` encode the real read graph from `envs/**` `terraform_remote_state` blocks. Opt-in cross-cloud edges (saas secret bridge, cross-cloud references) via `extra_remote_state_consumers`. |
| Health assessments | `enable_health_assessments` (default true): native drift detection + continuous validation. |
| Dynamic credentials | Per-workspace `TFC_GCP_*` / `TFC_AWS_*` env vars, set only when their inputs are supplied (see below). |
| Variables | Org-wide values in the `<prefix>common` variable set (attached to every workspace); per-workspace values via `workspace_variables`; `gcp-workload-<env>` gets `environment` derived from its name. |
| Policy | Optional OPA policy set from `policies/opa/` (`enable_policy_sets`, default false; policies are advisory). |

## Two-pass bootstrap (dynamic credentials)

The plan/apply identities are created by roots whose workspaces this root creates:

1. Apply tfc-admin: workspaces exist, no credential env vars yet.
2. Apply `gcp-bootstrap` (phase-0) and/or `aws-organization`.
3. Feed their outputs back, either by copying them into
   `gcp_workload_provider_name`, `gcp_plan_service_accounts`, `gcp_apply_service_accounts`,
   `aws_plan_role_arns`, `aws_apply_role_arns` (maps keyed by workspace name), or by
   setting `gcp_bootstrap_outputs_from_tfc` / `aws_organization_outputs_from_tfc = true`
   (read via `tfe_outputs`; AWS maps workspace => account key from aws-organization
   `tfc_workspace_bindings`, overridable via `aws_workspace_account_keys`). tfc-admin is then added as a remote-state consumer of those producers.
4. Re-apply tfc-admin.

See [docs/runbooks/bootstrap.md](../../docs/runbooks/bootstrap.md) and
[docs/guides/CI_SECRETS.md](../../docs/guides/CI_SECRETS.md).

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
