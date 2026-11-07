# Branch Protection Policy

Recommended GitHub branch protection settings for this repository. Apply these before granting team access.

---

## `main` Branch

### Status Checks (required before merge)

Require **exactly one** status-check context: **`Validation Summary`** (the `summary`
job in `terraform-plan.yml`).

| Required context | Source job |
|------------------|-----------|
| `Validation Summary` | `summary` (fail-closed aggregator) |

`Validation Summary` `needs:` every other PR job — `discover`, `fmt`, `docs`, `validate`,
`lint`, `meta-lint`, `security`, `test`, `shellcheck`, `opa`, `codeowners` — runs with
`if: always()`, and fails closed if any of them failed **or was skipped**. One stable
context therefore gates every check, and adding or renaming a job never needs a
branch-protection change.

Do **not** add the individual job contexts. Several emit a different context per run
shape and would block every PR forever if listed verbatim:

- **Sharded matrix jobs** emit one context *per shard*, never a bare name:
  `Validate (shard N)` (10 shards) and `Terraform Tests (shard N)` (6 shards). A
  required `Terraform Tests` or `validate` context is never reported, so GitHub waits
  on it indefinitely. The shard count can also change.
- **The `security` job calls a reusable workflow**, so its contexts are
  `Security / Trivy` and `Security / Checkov` — never a bare `security`.

`scripts/check-required-checks.sh` (run in the `Meta Lint` job) parses the `gh api`
command below and fails if any listed context is not a non-matrix job `name:` in
`.github/workflows/`, so this doc cannot drift into an unsatisfiable list again.

`security-scan.yml` (`static-analysis`, `trivy`, `secret-scan`, `summary`) runs on **push to `main`/`develop` and weekly on schedule** — it never runs on `pull_request`, so its jobs **cannot** be configured as required status checks; doing so would make `main` permanently unmergeable. Treat it as a non-blocking, post-merge/scheduled signal instead (monitor its `summary` job for regressions).

Set via **Settings → Branches → main → Require status checks to pass before merging**.

> **The repo checks validate; they do not plan (audit H6).** `Validation Summary`
> and every job it gates run `terraform validate -backend=false` and the `mock_provider` tests. None
> runs a real plan against state, so none shows the blast radius of a change. The
> actual plan is Terraform Cloud's **speculative plan**, posted as its own check
> (e.g. `Terraform Cloud/<org>/<workspace>`) by the TFC VCS integration. For roots
> that gate production, ADD those TFC checks to the required contexts, so "all checks
> passed" cannot be green while the real plan errored or was never reviewed. They are
> external checks, so `scripts/check-required-checks.sh` ignores contexts that start
> with `Terraform Cloud/`.

### TFC organization owners

AWS OIDC trust can condition only on the token claims `aud`, `sub`, `amr`,
`email` and `oaud`, so every `tfc-plan`/`tfc-apply` role trusts a **workspace
name**. Whoever can create or rename a workspace can assume those roles. So:

- Keep **at least 2** TFC organization owners (a lone owner is a lockout risk).
- Owners are **never used day to day**. Work runs as the `platform` team, whose
  custom access (`envs/tfc-admin/main.tf`) already forbids creating or renaming
  workspaces.
- Only owners may rename or create workspaces.
- Control-plane workspaces, including `aws-network`, are in
  `speculative_disabled_workspaces`, so a PR never gets a plan with their
  credentials.

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
  --field required_status_checks='{"strict":true,"contexts":["Validation Summary"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":true}' \
  --field restrictions=null \
  --field required_linear_history=true
```

---

## Release Tag Protection

Tags that trigger the `terraform-apply.yml` workflow should be protected. The
workflow acts on all of these patterns (keep this list in sync with its `on.push.tags`):
`gcp-organization/v*`, `gcp-workload/*/v*`, `aws-*/v*`, `aws-workload/*/v*`, `saas/*/v*`.

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
  --field conditions='{"ref_name":{"include":["refs/tags/gcp-organization/v*","refs/tags/gcp-workload/*/v*","refs/tags/aws-*/v*","refs/tags/aws-workload/*/v*","refs/tags/saas/*/v*"],"exclude":[]}}' \
  --field rules='[{"type":"deletion"},{"type":"non_fast_forward"}]'
```

---

### Release gate: `Sandbox convergence`

Once the sandbox workflow exists, add **`Sandbox convergence`** (HCP Terraform health-assessment result for the sandbox) as a required check on release-please PRs (head branch `release-please--*`), via a ruleset scoped to that branch pattern. It is not a required context on ordinary PRs. Until the workflow lands the check does not exist and the release PR is gated by maintainer review only; do not add it as a required context before it reports, or releases will block.

---

## Dependabot Security Updates

Ensure Dependabot auto-approves and merges **security** PRs only:

1. **Settings → Code security and analysis → Dependabot security updates**: Enable
2. **Settings → Code security and analysis → Dependabot version updates**: Review `.github/dependabot.yml`. It covers GitHub Actions and the CI Python tooling only. Terraform providers and `.terraform.lock.hcl` files are owned by Renovate (`renovate.json`): one grouped weekly PR per provider family, labelled for REVIEW, never auto-merged, with provider majors disabled so they stay deliberate (see `docs/guides/provider-upgrades.md`)
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
