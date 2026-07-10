# CI Secrets & Variables

Repository secrets and variables referenced by `.github/workflows/`. Configure these under
**Settings → Secrets and variables → Actions** before relying on the workflows below.

---

## Required

| Name | Kind | Used by | Purpose |
|------|------|---------|---------|
| `TFC_TOKEN` | Secret | `drift-detection.yml`, `terraform-apply.yml` | Terraform Cloud API token (Team or Organization token) used to query workspace runs and trigger speculative plans. |
| `TFC_ORGANIZATION` | Variable | `drift-detection.yml`, `terraform-apply.yml` | Terraform Cloud organization name that owns the workspaces. |

Without both of these, `drift-detection.yml` **skips cleanly** on its scheduled runs (see
"Drift detection behavior without secrets" below) rather than failing red. `terraform-apply.yml`
requires them to function since it drives real applies via the TFC API.

## AWS roots — dynamic credentials

The AWS roots (`envs/aws-*`) do not use static access keys in CI. Each root authenticates via
**Terraform Cloud dynamic provider credentials**: TFC federates into an IAM role at run time
and injects short-lived credentials, so no long-lived secret is stored. These are set as
**workspace environment variables** on each `aws-*` workspace (not repository secrets):

| Name | Kind | Scope | Purpose |
|------|------|-------|---------|
| `TFC_AWS_PROVIDER_AUTH` | Workspace env var | Per `aws-*` workspace | Set to `true` to enable TFC's AWS dynamic credentials for the workspace. |
| `TFC_AWS_RUN_ROLE_ARN` | Workspace env var | Per `aws-*` workspace | The IAM role ARN the run assumes. Set each downstream workspace to its member-account role, published by the `aws-organization` root output `account_role_arns[<account-key>]` (e.g. `account_role_arns["security_tooling"]` for `aws-security`). The `aws-organization` workspace itself uses the phase-0 bootstrap role. |

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
| `TFC_DRIFT_WORKSPACES` | Variable | `drift-detection.yml` | JSON array of TFC workspace names to check for drift, e.g. `["organization","apps-dev","apps-prod"]`. | `["organization","apps-dev"]` |
| `DOCS_BOT_PAT` | Secret | `documentation.yml` | Machine-account PAT (repo scope) used to open auto-generated docs PRs so they trigger downstream CI. `GITHUB_TOKEN`-authored PRs do not trigger other workflows. | Falls back to `secrets.GITHUB_TOKEN` (docs PRs will not trigger CI checks). |
| `DOCS_REVIEWER` | Variable | `documentation.yml` | GitHub username to request as reviewer on auto-generated docs PRs. | No reviewer requested. |

## Drift detection behavior without secrets

`drift-detection.yml` runs a `check-credentials` job before the matrix job. It evaluates
`secrets.TFC_TOKEN` and `vars.TFC_ORGANIZATION` (secrets cannot be referenced directly in a
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
