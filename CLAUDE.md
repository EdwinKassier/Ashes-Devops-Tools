# CLAUDE.md — Agent Onboarding

Terraform GCP + AWS landing zone. 89 modules, 10 deployable roots, remote state via Terraform Cloud.

---

## Repo Layout

```text
envs/
  organization/         # GCP control plane: folders, org policies, KMS, network hub, bootstrap WIF
  apps/                 # GCP per-environment app infra — TF_WORKSPACE=apps-<env>
  aws-organization/     # AWS foundational accounts + org structure
  aws-security/         # AWS security tooling / log archive (min baseline w/ aws-organization)
  aws-network/          # AWS shared networking
  aws-identity/         # AWS IAM Identity Center / SSO
  aws-shared-services/  # AWS shared platform services
  aws-backup/           # AWS centralized backup
  aws-workload/         # AWS per-env workloads — TF_WORKSPACE=aws-workload-<env>
  saas/                 # Supabase and/or Vercel only — TF_WORKSPACE=saas-<name>

modules/
  stages/         # Orchestration wrappers: bootstrap, organization, projects,
                  #   network-hub, workload, saas-workload
  network/        # ~19 primitives: vpc, subnet, dns, vpn, vpc-sc, cloud-armor, …
  governance/     # billing, kms, org-policy, scc, tags, cloud-audit-logs
  iam/            # organization, role, service-account, workload-identity, identity-group*
  supabase/       # project, settings, environment, vault-secrets
  vercel/         # project
  host/           # compatibility wrapper for envs/apps
  monitoring/     # alert-policy, compute-dashboard
  firebase/       # project
  cloud-storage/
  artifact-registry/
  aws/            # AWS modules (organization, security, network, identity, backup, workload, …)
```

---

## Choosing providers

Deploy **any combination** of `{aws, gcp, supabase, vercel}`. Each cloud has its own root(s) and TFC workspace(s), so an unused cloud's provider is physically absent from the roots you apply.

A `provider` block cannot be conditional, and Terraform authenticates any referenced provider even at `count = 0` — so **cloud selection is which workspaces you apply, not a runtime `enable_<cloud>` flag**. `enable_*` flags only gate features *within* a root (`enable_supabase`, `enable_vercel`, `enable_edge`).

Full rationale, root inventory, and the any-combination matrix: [`docs/architecture/provider-selection.md`](docs/architecture/provider-selection.md).

---

## Toolchain Requirements

| Tool | Required version |
|------|-----------------|
| Terraform | `~> 1.9` (uses `mock_provider`, `override_module`, `terraform_data`) |
| google / google-beta | `~> 6.0` |
| hashicorp/aws | `>= 6.46.0, < 7.0.0` (floored pin — deliberate, not `~> 6.0`) |
| supabase/supabase | `~> 1.0` |
| vercel/vercel | `~> 4.0` |
| hashicorp/null | `~> 3.0` |

---

## Makefile Quick Reference

```bash
make fmt-check      # terraform fmt -check (CI gate)
make docs           # terraform-docs on every module (auto-generates READMEs)
make docs-check     # same but exits non-zero if READMEs are stale
make test           # runs all *.tftest.hcl with mock_provider — no real creds needed
make validate-all   # terraform validate across all modules
make lint           # tflint
make security       # tfsec + checkov
make ci             # fmt-check + docs-check + validate-all + lint + security + test
```

---

## Testing

- Tests live alongside modules as `*.tftest.hcl`.
- `make test` calls `terraform test` with `mock_provider` — **no real cloud credentials needed**.
- Always run `make test` before opening a PR.

---

## State & Apply Rules

- State backend: **Terraform Cloud** (remote).
- **Never run `terraform apply` locally** against `envs/organization` or `envs/apps`.
- CI (GitHub Actions) runs `fmt`, `validate`, `lint`, `tfsec`, `checkov` on PR.
- Terraform Cloud executes the actual apply.

---

## Required Environment Variables

Only the roots you apply pull in credentials — an unapplied workspace needs none. See [Choosing providers](#choosing-providers).

| Variable | Purpose |
|----------|---------|
| `GOOGLE_CLOUD_PROJECT` / GCP ADC | google provider — GCP roots (`organization`, `apps`) only |
| `TFC_AWS_PROVIDER_AUTH` + `TFC_AWS_RUN_ROLE_ARN` | AWS via TFC dynamic (OIDC) credentials — AWS roots only |
| `AWS_PROFILE` | AWS local/OIDC fallback when not using TFC dynamic credentials — AWS roots only |
| `SUPABASE_ACCESS_TOKEN` | supabase provider — `saas` root only, when `enable_supabase=true` |
| `VERCEL_API_TOKEN` | vercel provider — `saas` root only, when `enable_vercel=true` |
| `TFC_TOKEN` | Terraform Cloud API — always |

---

## Module Authoring Rules

### Docs

Every module README must have these markers for `make docs` to work:

```markdown
<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
```

Run `make docs` after adding/changing variables or outputs.

### Sensitive values in `null_resource` triggers

Terraform 1.9 rejects raw sensitive values in triggers. Always hash them:

```hcl
triggers = {
  secret_hash = nonsensitive(sha256(var.sensitive_var))
}
```

### Vercel provider v4 — `git_repository`

`git_repository` is a Single Nested Attribute in v4. Use assignment syntax, not block syntax:

```hcl
# CORRECT
git_repository = {
  type = "github"
  repo = "org/repo"
}

# WRONG — block syntax
git_repository {
  type = "github"
  repo = "org/repo"
}
```

### Supabase `anon_key`

The provider marks `anon_key` sensitive. Unwrap it explicitly in outputs:

```hcl
value = nonsensitive(data.supabase_apikeys.this.anon_key)
```

### Vercel `ignore_command` scripts

Vercel executes `ignore_command` in `/bin/sh`, not bash. Use POSIX sh syntax:

```sh
# CORRECT
[ "$VERCEL_ENV" = "production" ]

# WRONG
[[ "$VERCEL_ENV" == "production" ]]
```

### vault-secrets Node.js dependency

`modules/supabase/vault-secrets/scripts/` requires Node.js dependencies before first apply with `enable_vault_secrets = true`:

```bash
cd modules/supabase/vault-secrets/scripts/
npm install
```

---

## Navigating the Codebase

| Goal | Where to look |
|------|--------------|
| Org-level GCP resources | `envs/organization/` |
| Per-env app infra | `envs/apps/` (set `TF_WORKSPACE=apps-<env>`) |
| Full end-to-end workload | `modules/stages/workload/` or `modules/stages/saas-workload/` |
| VPC / networking | `modules/network/` |
| IAM / service accounts | `modules/iam/` |
| KMS / billing / org policy | `modules/governance/` |
| Supabase integration | `modules/supabase/` |
| Vercel integration | `modules/vercel/` |
| Alerts / dashboards | `modules/monitoring/` |

---

## Common Workflows

### Adding a new module

1. Create `modules/<category>/<name>/`.
2. Add `main.tf`, `variables.tf`, `outputs.tf`.
3. Add README with `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers.
4. Add a `*.tftest.hcl` with at least one `mock_provider` test.
5. Run `make docs && make test && make ci`.

### Updating an existing module

1. Edit the module.
2. Run `make docs` to regenerate the README section.
3. Run `make test` to verify.
4. Run `make ci` before pushing.

### Working with environments

```bash
# Target a specific app environment
export TF_WORKSPACE=apps-staging
cd envs/apps
terraform plan   # read-only local check — apply only via TFC
```
