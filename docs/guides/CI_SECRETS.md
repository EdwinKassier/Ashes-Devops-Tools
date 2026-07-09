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
