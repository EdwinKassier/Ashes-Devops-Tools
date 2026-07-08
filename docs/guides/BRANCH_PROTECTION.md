# Branch Protection Policy

Recommended GitHub branch protection settings for this repository. Apply these before granting team access.

---

## `main` Branch

### Status Checks (required before merge)

All of the following CI jobs must pass:

| Workflow | Jobs required |
|----------|--------------|
| `terraform-plan.yml` | `fmt`, `docs-check`, `validate`, `lint`, `security` |
| `security-scan.yml` | `tfsec-modules`, `tfsec-envs`, `checkov`, `trivy`, `gitleaks` |

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
  --field required_status_checks='{"strict":true,"contexts":["fmt","docs-check","validate","lint","security","tfsec-modules","tfsec-envs","checkov","trivy","gitleaks"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":true}' \
  --field restrictions=null \
  --field required_linear_history=true
```

---

## Release Tag Protection

Tags that trigger the `terraform-apply.yml` workflow (`organization/v*`, `apps/*/v*`) should be protected:

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
  --field conditions='{"ref_name":{"include":["refs/tags/organization/v*","refs/tags/apps/*/v*"],"exclude":[]}}' \
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
