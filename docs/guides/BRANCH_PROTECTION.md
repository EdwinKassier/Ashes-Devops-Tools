# Branch Protection Policy

Recommended GitHub branch protection settings for this repository. Apply these before granting team access.

---

## `main` Branch

### Status Checks (required before merge)

Required status-check **contexts** are the job **display names** (`name:`), not the job
IDs — and for the reusable security workflow they are prefixed by the calling job's
name. Use exactly these strings from `terraform-plan.yml`:

| Required context | Source job |
|------------------|-----------|
| `Terraform Format` | `fmt` |
| `Terraform Docs Check` | `docs` |
| `TFLint` | `lint` |
| `Meta Lint (yaml/markdown/commits)` | `meta-lint` |
| `Terraform Tests` | `test` |
| `Security / TFSec` | `security` → reusable `tfsec` |
| `Security / Checkov` | `security` → reusable `checkov` |
| `Validation Summary` | `summary` (fail-closed aggregator) |

Two important gotchas this list already accounts for:

- **The `validate` job is a matrix** (`name: Validate ${{ matrix.root }}`) that emits one
  context *per root* (~180 of them), never a single `validate` context. Do **not** list
  `validate` (or per-leg names) as required — they change as roots are added/removed.
  Instead require **`Validation Summary`**, which `needs:` the whole matrix and fails
  closed if any leg fails, so it gates the matrix through one stable context.
- **The `security` job calls a reusable workflow**, so its contexts are
  `Security / TFSec` and `Security / Checkov` — never a bare `security`.

`security-scan.yml` (`static-analysis`, `trivy`, `secret-scan`, `summary`) runs on **push to `main`/`develop` and weekly on schedule** — it never runs on `pull_request`, so its jobs **cannot** be configured as required status checks; doing so would make `main` permanently unmergeable. Treat it as a non-blocking, post-merge/scheduled signal instead (monitor its `summary` job for regressions).

Set via **Settings → Branches → main → Require status checks to pass before merging**.

### Review Requirements

- **Required approvals:** 1 (raise to 2 for teams larger than 4)
- **Dismiss stale reviews:** enabled (new commits invalidate prior approval)
- **Require CODEOWNERS review:** enabled (`.github/CODEOWNERS` enforced)
- **Restrict who can bypass:** disable bypass for administrators

### Additional Restrictions

- **Require branches to be up to date** before merging (prevents race conditions on shared state)
- **Require linear history** (recommended — keeps `git log` clean for releases)
- **Require signed commits** if your team has GPG/SSH signing configured

### Apply via GitHub CLI

```bash
gh api repos/OWNER/REPO/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Terraform Format","Terraform Docs Check","TFLint","Meta Lint (yaml/markdown/commits)","Terraform Tests","Security / TFSec","Security / Checkov","Validation Summary"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":true}' \
  --field restrictions=null \
  --field required_linear_history=true
```

---

## Release Tag Protection

Tags that trigger the `terraform-apply.yml` workflow (`gcp-organization/v*`, `gcp-workload/*/v*`) should be protected:

- Only allow tag creation by the **infra-admins** team or repository admins
- Require signed tags if your signing policy enforces it
- Never force-push to release tags

```bash
# Create a tag ruleset (GitHub Enterprise or GitHub.com with rulesets beta)
gh api repos/OWNER/REPO/rulesets \
  --method POST \
  --field name="Release tag protection" \
  --field target="tag" \
  --field enforcement="active" \
  --field conditions='{"ref_name":{"include":["refs/tags/gcp-organization/v*","refs/tags/gcp-workload/*/v*"],"exclude":[]}}' \
  --field rules='[{"type":"deletion"},{"type":"non_fast_forward"}]'
```

---

## Dependabot Security Updates

Ensure Dependabot auto-approves and merges **security** PRs only:

1. **Settings → Code security and analysis → Dependabot security updates**: Enable
2. **Settings → Code security and analysis → Dependabot version updates**: Review `.github/dependabot.yml` (scoped to GitHub Actions only — Terraform provider bumps require manual compatibility work, see `docs/guides/provider-upgrades.md`)
3. Create a branch protection rule that allows Dependabot to bypass review requirements for patch-level security updates

---

## Environment Secrets

Secrets required by CI/CD — scope each to the minimum environment:

| Secret | Scope | Purpose |
|--------|-------|---------|
| `TFC_TOKEN` | Repository | Read-only TFC team token for run status verification |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Repository | WIF provider name for GCP authentication |
| `GCP_SERVICE_ACCOUNT` | Repository | Terraform admin SA for plan/apply |

**Never** store these as user-level secrets. Use repository or environment-scoped secrets only.

For `TFC_TOKEN`: create a **team token** in Terraform Cloud with **Read** permission on workspace runs only — not an org-level or user token.

---

## Merge Queue (Optional)

For high-velocity teams, enable GitHub's merge queue to serialize concurrent merges:

**Settings → General → Merge queue** → Enable for `main`

This prevents the "test passes individually but breaks together" problem when multiple PRs target the same `main`.
