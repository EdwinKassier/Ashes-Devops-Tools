# CI Secrets & Variables

Repository secrets and variables referenced by `.github/workflows/`. Configure these under
**Settings → Secrets and variables → Actions** before relying on the workflows below.

---

## Required

| Name | Kind | Used by | Purpose |
|------|------|---------|---------|
| `TFC_TOKEN` | Secret | `terraform-apply.yml` | Terraform Cloud team token with **READ** access to workspace runs. Used only to verify run status before publishing a release; it does not trigger or modify runs. |
| `TFC_TOKEN_GUARDRAILS` | Secret (environment `tfc-readonly`) | `terraform-apply.yml` | Token of the team set as tfc-admin `guardrails_release_reader_team_id`: runs = read on the guardrails project only (no state, no variables). Needed only for `gcp-guardrails/v*` tags, because `gcp-guardrails` sits in a security-only project that `TFC_TOKEN` cannot see. There is no fallback to `TFC_TOKEN`: a guardrails tag without this secret fails. An organization owner creates the team and its token by hand with an expiry, never with `tfe_team_token`, so it stays out of state. |
| `TFC_TOKEN_DRIFT` | Secret | `drift-detection.yml` | Token of the team set as tfc-admin `drift_team_id`. tfc-admin codifies its grants: **Queue Plans** (`runs = plan`), **Read state versions** and no variable access, on every project except guardrails and the secret-bearing projects (tfc-admin, `saas-*`, and any project that holds a workspace with a static secret). An organization owner creates the token by hand with an expiry (`expired_at` 90 days out) and never with `tfe_team_token`, so it stays out of state. Never use a token with rights on a secret-bearing project: a refresh-only plan still runs with the workspace's variables. On those workspaces HCP health assessments (`enable_health_assessments`) are the only drift check, and only on tiers that offer them. Drift detection reads the current state version to find the last applied run and its configuration version, then creates a speculative refresh-only run pinned to that configuration (`POST /runs`), which read access cannot do. Merged but unapplied configuration is reported as a separate warning, not as drift. There is **no fallback** to `TFC_TOKEN`: if unset, scheduled runs skip and manual runs fail with an explicit error, so the release token is never silently granted Queue Plans. |
| `TFC_ORGANIZATION` | Variable | `drift-detection.yml`, `terraform-apply.yml` | Terraform Cloud organization name that owns the workspaces. |
| `RELEASE_APP_ID` | Variable (`release` environment) | `release.yml` | ID of the release GitHub App. **Required; no fallback.** See [below](#release_app). |
| `RELEASE_APP_PRIVATE_KEY` | Secret (`release` environment) | `release.yml` | Private key of the release GitHub App. The workflow mints a one-hour token from it on every run. **Required; no fallback.** See [below](#release_app). |

Without both of these, `drift-detection.yml` **fails**, unless the repository variable
`REAL_CLOUD_CHECKS_OPT_OUT=true` acknowledges running without it (see "Drift detection
behavior without secrets" below). `terraform-apply.yml`
does NOT apply anything: the real apply is driven by Terraform Cloud's own VCS integration.
That workflow only reads the latest TFC run status with the read-only `TFC_TOKEN` and publishes
a GitHub Release when the run applied and its commit matches the tag. The run's commit is the
`commit-sha` of its configuration version's ingress attributes
(`scripts/verify-run-commit.sh`); a run with none, such as a CLI or API run, fails the
workflow and publishes nothing. (The workflow is named
"Terraform Release Metadata" for this reason; `terraform-plan.yml`, named "Terraform Validation",
runs `terraform validate` and the mock tests, and likewise never produces a real plan - that is
the TFC speculative plan.)

## DOCS_BOT_PAT

`documentation.yml` opens a PR with regenerated module READMEs. A PR authored by `GITHUB_TOKEN`
does not trigger other workflows, so it would skip validation; a PAT-authored PR does. Use a
**fine-grained** personal access token of a dedicated machine account, never a classic `repo`
token:

- **Resource owner / repository access:** this repository only.
- **Repository permissions:** Contents: read and write; Pull requests: read and write;
  Metadata: read (implicit). Nothing else, and no `workflow` scope.
- **Expiry:** at most 90 days. Rotate it, or replace it with a GitHub App installation token.
- **Storage:** as an *environment* secret in `docs-bot` (deployment branch `main` only), not at
  repository level.

The workflow passes it only to `peter-evans/create-pull-request`. The checkout step uses
`persist-credentials: false` and the default read-only clone, so `make docs` never runs next to
a stored credential. If the secret is unset the workflow falls back to `GITHUB_TOKEN` and the
docs PR will not trigger CI.

## release_app

`release.yml` runs on every push to `main`. It uses one GitHub App, the release bot, as its
identity. The workflow mints an installation token that lasts one hour at the start of each run,
so no long-lived personal access token exists. The first step **fails** with
`Release App missing` when the variable `RELEASE_APP_ID` or the secret
`RELEASE_APP_PRIVATE_KEY` is unset. It deliberately does not fall back to `GITHUB_TOKEN`: a pull
request opened with `GITHUB_TOKEN` does not trigger `pull_request` workflows, so the release PR
would never receive the required **Validation Summary** check and could never merge under branch
protection. A red run that names the missing setting is a better signal than a release PR that
is stuck forever.

Set it up once (repository admin):

1. Go to **Settings, Developer settings, GitHub Apps, New GitHub App**. Name it
   `ashes-release-bot`. Turn webhooks off.
2. Give it these repository permissions: **Contents: Read and write**, **Pull requests: Read and
   write**, **Issues: Read and write** (release-please creates its `autorelease:*` labels) and
   **Metadata: Read**. Install it on this repository only.
3. Generate a private key, then store both values in the `release` environment:

   ```bash
   gh variable set RELEASE_APP_ID --env release --body "<app id>"
   gh secret set RELEASE_APP_PRIVATE_KEY --env release < ashes-release-bot.private-key.pem
   rm -P ashes-release-bot.private-key.pem   # macOS; use shred -u on Linux
   gh workflow run release.yml
   ```

4. If a ruleset protects the `vX.Y.Z` tags, add the App as a bypass actor so release-please can
   create the tag.

Forks and clones that do not cut releases can disable the workflow instead
(**Actions, Release, Disable workflow**). Rotate the private key on a schedule: generate a new
key, update the secret, then delete the old key in the App settings.

## Dynamic provider credentials (GCP and AWS roots) — managed by tfc-admin

No cloud root uses static keys. Each workspace authenticates via **HCP Terraform dynamic
provider credentials** (OIDC/WIF): TFC federates into a cloud identity at run time with
separate **plan** (read-only) and **apply** identities. These are **workspace environment
variables**, not repository secrets, and they are written by the
[`envs/tfc-admin`](../../envs/tfc-admin/README.md) root — do not hand-set them in the UI
(tfc-admin would revert them). They are only set on a workspace once its inputs are supplied.

| Env var | Workspaces | Source (tfc-admin input, or upstream output via `tfe_outputs`) |
|---------|-----------|-----------------------------------------------------------------|
| `TFC_GCP_PROVIDER_AUTH` = `true` | `gcp-*` with an SA | set automatically |
| `TFC_GCP_WORKLOAD_PROVIDER_NAME` | `gcp-*` with an SA | `gcp_workload_provider_name` ← gcp-bootstrap `tfc_workload_provider_name` |
| `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` | per `gcp-*` | `gcp_plan_service_accounts[<ws>]` ← gcp-bootstrap `tfc_plan_service_accounts` |
| `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL` | per `gcp-*` | `gcp_apply_service_accounts[<ws>]` ← gcp-bootstrap `tfc_apply_service_accounts` |
| `TFC_AWS_PROVIDER_AUTH` = `true` | `aws-*` with a role | set automatically |
| `TFC_AWS_PLAN_ROLE_ARN` | per `aws-*` | `aws_plan_role_arns[<ws>]` ← aws-organization `tfc_plan_role_arns[<account-key>]` via `tfc_workspace_bindings` / `aws_workspace_account_keys` |
| `TFC_AWS_APPLY_ROLE_ARN` | per `aws-*` | `aws_apply_role_arns[<ws>]` ← aws-organization `tfc_apply_role_arns[<account-key>]` via `tfc_workspace_bindings` / `aws_workspace_account_keys` |

Wiring is two-pass because the identities are created by roots whose workspaces tfc-admin
creates: apply tfc-admin → apply gcp-bootstrap / aws-organization → feed their outputs back
(copy into the variables, or set `gcp_bootstrap_outputs_from_tfc` /
`aws_organization_outputs_from_tfc = true`) → re-apply tfc-admin. See
[`docs/runbooks/bootstrap.md`](../runbooks/bootstrap.md#creating-and-wiring-the-tfc-workspaces-tfc-admin-two-pass).
The `aws-organization` workspace itself uses the phase-0 bootstrap role.

For **local** runs against an AWS root (read-only `terraform plan`), use the standard AWS SDK
credential chain instead — `AWS_PROFILE` pointing at a profile that can assume the role, or an
OIDC/SSO session — rather than the TFC-injected credentials, which only exist inside a TFC run.

The SaaS root (`envs/saas`) declares **no AWS provider** and needs no AWS credentials. It
requires `SUPABASE_ACCESS_TOKEN` and/or `VERCEL_API_TOKEN` only for whichever feature is
enabled on that workspace (`enable_supabase` / `enable_vercel`).

See [`docs/runbooks/aws-bootstrap.md`](../runbooks/aws-bootstrap.md) for phase-0 creation of the
bootstrap role, the downstream member-account roles, and the workspaces that consume them.

### TFC team permissions and committed variables

tfc-admin grants TFC access least-privilege, so no single person both changes a control-plane
input and approves its apply:

- `platform_team_id`: **custom** access on projects holding control-plane workspaces
  (`runs = plan` by default, variables and state read-only, no policy overrides); fixed
  **write** on workload workspaces.
- `control_plane_approvers_team_id`: a separate, small team with `runs = apply` (variables
  read-only) on the control-plane projects. It must differ from the platform team.
- The OPA policy set is created with `overridable = false`: a mandatory policy failure cannot
  be overridden from the UI.
- Production workload workspaces (`is_production`) get no speculative PR plans, so PR code never
  runs with a production plan identity.

Workspace variables are code: they come from `config/landing-zone.yaml`,
`config/tfc-workspaces.yaml` (no secrets) or tfc-admin `workspace_variables`. TFC cannot stop an
organization owner from setting a UI variable, so keep the owners team tiny, give no other team
`variables = write` on the control plane, and treat a UI-set variable as drift (tfc-admin reverts
the ones it manages at its next apply).

## Optional

| Name | Kind | Used by | Purpose | Default when unset |
|------|------|---------|---------|---------------------|
| `TFC_HEALTH_ASSESSMENTS` | Variable | `drift-detection.yml` | Set to `true` when HCP Terraform health assessments are on (tfc-admin `enable_health_assessments`, default true; needs a tier that has them). They are the drift source of record, so the workflow skips with a notice and needs neither `TFC_TOKEN_DRIFT` nor `REAL_CLOUD_CHECKS_OPT_OUT`. It is your statement that they are on; the workflow does not check. | Unset: the workflow runs as the fallback, and both paths can report drift. |
| `TFC_DRIFT_WORKSPACES` | Variable | `drift-detection.yml` | JSON array of TFC workspace names to check for drift. Use the tfc-admin output `drift_workspaces` or a subset of it: a workspace outside it fails its leg, because the drift token has no access there. | `["gcp-bootstrap","gcp-organization","gcp-projects","gcp-network-hub","gcp-workload-dev","aws-organization","aws-security","aws-network"]` |
| `DOCS_BOT_PAT` | Secret | `documentation.yml` | Fine-grained PAT (see [below](#docs_bot_pat)) used to open auto-generated docs PRs so they trigger downstream CI. `GITHUB_TOKEN`-authored PRs do not trigger other workflows. | Falls back to `secrets.GITHUB_TOKEN` (docs PRs will not trigger CI checks). |
| `DOCS_REVIEWER` | Variable | `documentation.yml` | GitHub username to request as reviewer on auto-generated docs PRs. | No reviewer requested. |
| `TFC_TOKEN_STATE_BACKUP` | Secret | `state-backup.yml` | Team token of the dedicated state-backup team (`state_backup_team_id` in `envs/tfc-admin`: `state_versions = read`, nothing else). It reads every state file it is granted, so keep it in the `tfc-state-backup` environment. Excludes `saas-*` unless `enable_saas_state_backup = true`. See [state backup](../runbooks/state-backup.md). | Run fails unless `STATE_BACKUP_OPT_OUT=true` (scheduled runs only). |
| `STATE_BACKUP_S3_BUCKET`, `STATE_BACKUP_AWS_ROLE_ARN`, `STATE_BACKUP_AWS_REGION` | Variables | `state-backup.yml` | S3 target: an Object Lock, versioned, SSE-KMS bucket and the role GitHub OIDC assumes to write to it. | No S3 copy. With no target at all the run fails. |
| `STATE_BACKUP_GCS_BUCKET`, `STATE_BACKUP_GCP_WIF_PROVIDER`, `STATE_BACKUP_GCP_SA` | Variables | `state-backup.yml` | GCS target: a bucket with a locked retention policy and the service account the WIF principal impersonates. | No GCS copy. With no target at all the run fails. |
| `STATE_BACKUP_WORKSPACES` | Variable | `state-backup.yml` | JSON array of workspaces that must be exported; a missing one fails the run. | Every workspace the token can see. |
| `STATE_BACKUP_PREFIX` | Variable | `state-backup.yml` | Object-name prefix in the bucket. | `tfstate/` |
| `TFC_TOKEN_AUDIT_TRAIL` | Secret | `tfc-audit-trail.yml` | The organization's audit trail token (`authentication-token?token=audit-trails`; the API refuses user and team tokens). Use it rather than an organization token. Keep it in the `tfc-audit-trail` environment only. The workflow also uses `TFC_ORGANIZATION` and the `STATE_BACKUP_*` target variables. See [audit trail export](../runbooks/state-backup.md#audit-trail-export). | Export off: scheduled runs warn, a manual dispatch fails. HCP Terraform keeps 14 days. |
| `STATE_BACKUP_OPT_OUT` | Variable | `state-backup.yml` | `true` only to acknowledge running without a state copy outside HCP Terraform: unconfigured scheduled runs then warn instead of failing. | Unset: an unconfigured run fails. |
| `CODEOWNERS_ENFORCE` | Variable | `terraform-plan.yml` (CODEOWNERS placeholders job) | Set to `true` once `.github/CODEOWNERS` names real teams: any remaining `@your-org/` placeholder then fails the build. | Placeholders produce a warning only, so forks stay green. |
| `RENOVATE_HEARTBEAT_REQUIRED` | Variable | `dependency-heartbeat.yml` | Set to `true` in a fork that uses Renovate: the weekly heartbeat then fails when `renovate[bot]` has not updated an issue or pull request for 8 days. The upstream repository always fails on a stale heartbeat. | A fork gets a warning only, so a fork without Renovate stays green. |

## Sandbox E2E

Used by `sandbox-e2e.yml`, the real-apply suites in `tests/e2e/`. All are **repository
variables**, not secrets: both clouds authenticate keylessly (GCP Workload Identity
Federation, AWS GitHub OIDC), so there is nothing secret to store. When a cloud's
variables are unset the run **fails**. The one exception is a scheduled run with
`REAL_CLOUD_CHECKS_OPT_OUT=true`, which skips with a warning. Sandbox
setup, trust conditions and cost guardrails are in [Sandbox E2E](sandbox-e2e.md).

| Name | Kind | Used by | Purpose | Default when unset |
|------|------|---------|---------|---------------------|
| `E2E_GCP_WIF_PROVIDER` | Variable | `sandbox-e2e.yml` | Full WIF provider resource name: `projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`. | Run fails (see opt-out). |
| `E2E_GCP_SA` | Variable | `sandbox-e2e.yml` | Email of the sandbox runner service account that the WIF principal impersonates. | Run fails (see opt-out). |
| `E2E_GCP_PROJECT` | Variable | `sandbox-e2e.yml` | ID of the **dedicated, disposable** GCP sandbox project. Never a landing-zone project. | Run fails (see opt-out). |
| `E2E_GCP_REGION` | Variable | `sandbox-e2e.yml` | Region for the GCP suite's regional resources. | `europe-west2` |
| `E2E_AWS_ROLE_ARN` | Variable | `sandbox-e2e.yml` | ARN of the sandbox runner role assumed via GitHub OIDC. Its trust policy is pinned to `repo:<owner>/<repo>:environment:e2e-sandbox`. | Run fails (see opt-out). |
| `E2E_AWS_REGION` | Variable | `sandbox-e2e.yml` | Region of the **dedicated, disposable** AWS sandbox account. | Run fails (see opt-out). |
| `REAL_CLOUD_CHECKS_OPT_OUT` | Variable | `sandbox-e2e.yml`, `drift-detection.yml` | Set to `true` only to acknowledge that this estate runs **without** real-cloud verification. Scheduled E2E and drift runs then skip with a warning instead of failing. The summary never reports "no drift" for a run that did not happen. | Unset: unconfigured checks fail. |

The cloud jobs run in the `e2e-sandbox` GitHub environment, which gives them a stable OIDC
subject. The preflight job has no environment, so it reads repository-level variables
only. Set the variables above at repository level.

## Environment-scoped secrets

A repository-level secret is readable by **any workflow on any branch**. Anyone with write
access could push a branch whose workflow prints `secrets.TFC_TOKEN_DRIFT`. The jobs that use a
privileged secret therefore run in a GitHub **environment**. Store each secret in that
environment, not at repository level, and restrict the environment's deployment branches:

| Environment | Secrets | Deployment branch / tag policy | Used by |
|---|---|---|---|
| `tfc-drift` | `TFC_TOKEN_DRIFT` | `main` only | `drift-detection.yml` |
| `release` | `RELEASE_APP_PRIVATE_KEY` (plus variable `RELEASE_APP_ID`) | `main` only | `release.yml` |
| `docs-bot` | `DOCS_BOT_PAT` (optional) | `main` only | `documentation.yml` |
| `tfc-state-backup` | `TFC_TOKEN_STATE_BACKUP` | `main` only | `state-backup.yml` |
| `tfc-audit-trail` | `TFC_TOKEN_AUDIT_TRAIL` | `main` only | `tfc-audit-trail.yml` |
| `tfc-readonly` | `TFC_TOKEN`, `TFC_TOKEN_GUARDRAILS` | tags `gcp-bootstrap/v*`, `gcp-organization/v*`, `gcp-guardrails/v*`, `gcp-projects/v*`, `gcp-network-hub/v*`, `gcp-workload/*/v*`, `aws-*/v*`, `aws-workload/*/v*`, `saas/*/v*`, `tfc-admin/v*` | `terraform-apply.yml` |
| `e2e-sandbox` | none (OIDC only) | `main`, plus PR branches if you use the `e2e` label. **Required reviewers: yes** (at least one, prevent self-review) | `sandbox-e2e.yml` |

```bash
repo=OWNER/REPO
for env in tfc-drift tfc-state-backup tfc-audit-trail release docs-bot; do
  gh api -X PUT "repos/$repo/environments/$env" \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true'
  gh api -X POST "repos/$repo/environments/$env/deployment-branch-policies" -f name=main -f type=branch
done
gh secret set TFC_TOKEN_DRIFT --env tfc-drift        # then delete the repo-level copy:
gh secret delete TFC_TOKEN_DRIFT                      # (repeat for each secret)
```

The workflows already name these environments. GitHub creates an environment, unprotected, the
first time a job references it, so the branch policy above is what makes the scoping real.

**Deployment tags need a tag ruleset (CICD-1).** A tag policy on `tfc-readonly` admits any
matching tag on any commit. A tag push runs the workflow file of the tagged commit, so a writer
who tags a branch commit controls the job that holds `TFC_TOKEN`. `terraform-apply.yml` runs its
verifier from the default branch, keeps the token in the one `curl` step, and fails when the
tagged commit is not on the default branch, but a writer can edit those checks on the branch
commit. The control is a repository ruleset on tags that limits who can create, update and
delete the deployment tags to the release maintainers. The patterns below are the
`on.push.tags` list of `terraform-apply.yml`; `*` does not cross `/`, so the workload tags
(`gcp-workload/<env>/v*`, `aws-workload/<env>/v*`) are listed on their own.
`scripts/check-tag-patterns.py` (run by `make consistency`) fails when this list, the
`tfc-readonly` row above or `BRANCH_PROTECTION.md` drifts from the workflow:

```bash
gh api -X POST "repos/$repo/rulesets" --input - <<'JSON'
{"name": "deployment-tags", "target": "tag", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/tags/gcp-bootstrap/v*", "refs/tags/gcp-organization/v*", "refs/tags/gcp-guardrails/v*", "refs/tags/gcp-projects/v*", "refs/tags/gcp-network-hub/v*", "refs/tags/gcp-workload/*/v*", "refs/tags/aws-*/v*", "refs/tags/aws-workload/*/v*", "refs/tags/saas/*/v*", "refs/tags/tfc-admin/v*"], "exclude": []}},
 "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}],
 "bypass_actors": [{"actor_type": "RepositoryRole", "actor_id": 5, "bypass_mode": "always"}]}
JSON
# The tfc-readonly environment admits the same tags, one policy per pattern.
for p in 'gcp-bootstrap/v*' 'gcp-organization/v*' 'gcp-guardrails/v*' 'gcp-projects/v*' 'gcp-network-hub/v*' 'gcp-workload/*/v*' 'aws-*/v*' 'aws-workload/*/v*' 'saas/*/v*' 'tfc-admin/v*'; do
  gh api -X POST "repos/$repo/environments/tfc-readonly/deployment-branch-policies" -f name="$p" -f type=tag
done
```

`actor_id` 5 is the built-in admin role; use a maintainers team instead where you have one.
Prefer a GitHub App installation token over a `DOCS_BOT_PAT` PAT where
your organization allows it. The release workflow already does this.

## Drift detection behavior without secrets

HCP Terraform health assessments are the drift source of record. When they are on, set the
repository variable `TFC_HEALTH_ASSESSMENTS=true`: `drift-detection.yml` then skips with a
notice, and the rest of this section does not apply. The workflow is the fallback for tiers
without health assessments.

`drift-detection.yml` runs a `check-credentials` job before the matrix job. It evaluates
`secrets.TFC_TOKEN_DRIFT` and `vars.TFC_ORGANIZATION` (secrets cannot be referenced directly in a
job-level `if:`, so the check runs in a step and exposes a plain job output that the downstream
`if:` can read) and exposes a `configured` output:

- **Scheduled runs** (`schedule` trigger): if either value is missing, the credential check
  **fails** and the summary reports "Drift detection did NOT run". A green run that checked
  nothing would read as "no drift", which is the dangerous signal. To run without drift
  detection deliberately, set the repository variable `REAL_CLOUD_CHECKS_OPT_OUT=true`. The run
  then skips with a warning, and the summary still says drift is unmonitored.
- **Manual runs** (`workflow_dispatch`): always fail if either value is missing, whatever the
  opt-out, because a human explicitly asked for a drift check.

## Cross-checking this list

Run the following to find every `secrets.*`/`vars.*` reference in workflows and confirm this
table stays current:

```bash
grep -rn "secrets\.\|vars\." .github/workflows/
```
