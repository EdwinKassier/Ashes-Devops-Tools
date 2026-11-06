# CI Secrets & Variables

Repository secrets and variables referenced by `.github/workflows/`. Configure these under
**Settings → Secrets and variables → Actions** before relying on the workflows below.

---

## Required

| Name | Kind | Used by | Purpose |
|------|------|---------|---------|
| `TFC_TOKEN` | Secret | `terraform-apply.yml` | Terraform Cloud team token with **READ** access to workspace runs. Used only to verify run status before publishing a release; it does not trigger or modify runs. |
| `TFC_TOKEN_DRIFT` | Secret | `drift-detection.yml` | Terraform Cloud team token with **Queue Plans (write)** on the target workspaces. Drift detection creates speculative plan-only runs (`POST /runs`), which read access cannot do. There is **no fallback** to `TFC_TOKEN`: if unset, scheduled runs skip and manual runs fail with an explicit error, so the release token is never silently granted Queue Plans. |
| `TFC_ORGANIZATION` | Variable | `drift-detection.yml`, `terraform-apply.yml` | Terraform Cloud organization name that owns the workspaces. |
| `RELEASE_PLEASE_TOKEN` | Secret | `release.yml` | Machine-account token release-please uses to open the release PR and cut `vX.Y.Z` tags. **Required; no fallback.** See [below](#release_please_token). |

Without both of these, `drift-detection.yml` **skips cleanly** on its scheduled runs (see
"Drift detection behavior without secrets" below) rather than failing red. `terraform-apply.yml`
does NOT apply anything: the real apply is driven by Terraform Cloud's own VCS integration.
That workflow only reads the latest TFC run status with the read-only `TFC_TOKEN` and publishes
a GitHub Release when the run applied and its commit matches the tag. (The workflow is named
"Terraform Release Metadata" for this reason; `terraform-plan.yml`, named "Terraform Validation",
runs `terraform validate` and the mock tests, and likewise never produces a real plan - that is
the TFC speculative plan.)

## RELEASE_PLEASE_TOKEN

`release.yml` runs on every push to `main` and **fails on its first step** with
`RELEASE_PLEASE_TOKEN missing` when the secret is unset. It deliberately does not fall back
to `GITHUB_TOKEN`: a pull request opened with `GITHUB_TOKEN` does not trigger
`pull_request` workflows, so the release PR would never receive the required
**Validation Summary** check and could never merge under branch protection. A red run that
names the missing secret is a better signal than a release PR that is stuck forever.

Create one of the following and store it as the repository secret `RELEASE_PLEASE_TOKEN`:

- **Fine-grained PAT** on a machine account (preferred over a classic PAT), scoped to this
  repository only, with **Contents: Read and write**, **Pull requests: Read and write**
  and **Issues: Read and write** (release-please creates its `autorelease:*` labels).
  Give it an expiry and a calendar reminder to rotate it.
- **GitHub App installation token**: an App installed on this repository with the same three
  permissions. Mint the token in a step before release-please (for example with a SHA-pinned
  `actions/create-github-app-token`) and pass it in place of the secret.
- **Classic PAT** with `repo` scope: works, but is broader than needed.

The machine account must be allowed to push tags that your branch and tag rulesets protect.
Forks and clones that do not cut releases can disable the workflow instead
(**Actions → Release → Disable workflow**).

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

## Optional

| Name | Kind | Used by | Purpose | Default when unset |
|------|------|---------|---------|---------------------|
| `TFC_DRIFT_WORKSPACES` | Variable | `drift-detection.yml` | JSON array of TFC workspace names to check for drift, e.g. `["gcp-organization","gcp-workload-dev","gcp-workload-prod"]`. | `["gcp-organization","gcp-workload-dev"]` |
| `DOCS_BOT_PAT` | Secret | `documentation.yml` | Machine-account PAT (repo scope) used to open auto-generated docs PRs so they trigger downstream CI. `GITHUB_TOKEN`-authored PRs do not trigger other workflows. | Falls back to `secrets.GITHUB_TOKEN` (docs PRs will not trigger CI checks). |
| `DOCS_REVIEWER` | Variable | `documentation.yml` | GitHub username to request as reviewer on auto-generated docs PRs. | No reviewer requested. |
| `CODEOWNERS_ENFORCE` | Variable | `terraform-plan.yml` (CODEOWNERS placeholders job) | Set to `true` once `.github/CODEOWNERS` names real teams: any remaining `@your-org/` placeholder then fails the build. | Placeholders produce a warning only, so forks stay green. |

## Sandbox E2E

Used by `sandbox-e2e.yml`, the real-apply suites in `tests/e2e/`. All are **repository
variables**, not secrets: both clouds authenticate keylessly (GCP Workload Identity
Federation, AWS GitHub OIDC), so there is nothing secret to store. When a cloud's
variables are unset, that cloud's job is **skipped with a notice**, not failed. Sandbox
setup, trust conditions and cost guardrails are in [Sandbox E2E](sandbox-e2e.md).

| Name | Kind | Used by | Purpose | Default when unset |
|------|------|---------|---------|---------------------|
| `E2E_GCP_WIF_PROVIDER` | Variable | `sandbox-e2e.yml` | Full WIF provider resource name: `projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`. | GCP suite skipped. |
| `E2E_GCP_SA` | Variable | `sandbox-e2e.yml` | Email of the sandbox runner service account that the WIF principal impersonates. | GCP suite skipped. |
| `E2E_GCP_PROJECT` | Variable | `sandbox-e2e.yml` | ID of the **dedicated, disposable** GCP sandbox project. Never a landing-zone project. | GCP suite skipped. |
| `E2E_GCP_REGION` | Variable | `sandbox-e2e.yml` | Region for the GCP suite's regional resources. | `europe-west2` |
| `E2E_AWS_ROLE_ARN` | Variable | `sandbox-e2e.yml` | ARN of the sandbox runner role assumed via GitHub OIDC. Its trust policy is pinned to `repo:<owner>/<repo>:environment:e2e-sandbox`. | AWS suite skipped. |
| `E2E_AWS_REGION` | Variable | `sandbox-e2e.yml` | Region of the **dedicated, disposable** AWS sandbox account. | AWS suite skipped. |

The cloud jobs run in the `e2e-sandbox` GitHub environment, which gives them a stable OIDC
subject. The preflight job has no environment, so it reads repository-level variables
only. Set the variables above at repository level.

## Drift detection behavior without secrets

`drift-detection.yml` runs a `check-credentials` job before the matrix job. It evaluates
`secrets.TFC_TOKEN_DRIFT` and `vars.TFC_ORGANIZATION` (secrets cannot be referenced directly in a
job-level `if:`, so the check runs in a step and exposes a plain job output that the downstream
`if:` can read) and exposes a `configured` output:

- **Scheduled runs** (`schedule` trigger): if either value is missing, `detect-drift` is skipped
  (not failed) and the summary job reports "Skipped — Terraform Cloud credentials are not
  configured." A daily/weekday red workflow with no way to fix it (short of code changes) is a
  worse signal than an honest skip.
- **Manual runs** (`workflow_dispatch`): the credential check fails loudly (`exit 1`) if either
  value is missing, since a human explicitly asked for a drift check and silently skipping would
  be confusing.

## Cross-checking this list

Run the following to find every `secrets.*`/`vars.*` reference in workflows and confirm this
table stays current:

```bash
grep -rn "secrets\.\|vars\." .github/workflows/
```
