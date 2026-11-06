# CLAUDE.md — Agent Onboarding

Terraform GCP + AWS landing zone. 114 modules, 14 deployable roots, remote state via Terraform Cloud.

---

## Repo Layout

```text
envs/                   # deployable roots, nested by cloud (workspace names keep the flat gcp-/aws- form)
  gcp/
    bootstrap/          # GCP phase-0: admin project, Terraform admin SA, WIF pools — TF_WORKSPACE=gcp-bootstrap (apply first)
    organization/       # GCP control plane: folders, org policies, KMS, audit, billing (reads gcp-bootstrap)
    projects/           # GCP host/spoke projects + environment_config — TF_WORKSPACE=gcp-projects (reads gcp-organization)
    network-hub/        # GCP hub VPC, DNS anchor, hub VPC-SC — TF_WORKSPACE=gcp-network-hub (reads gcp-projects)
    workload/           # GCP per-environment app infra — TF_WORKSPACE=gcp-workload-<env>
  aws/
    organization/       # AWS foundational accounts + org structure
    security/           # AWS security tooling / log archive (min baseline w/ aws/organization)
    network/            # AWS shared networking
    identity/           # AWS IAM Identity Center / SSO
    shared-services/    # AWS shared platform services
    backup/             # AWS centralized backup
    workload/           # AWS per-env workloads — TF_WORKSPACE=aws-workload-<env>
  saas/                 # Supabase and/or Vercel only — TF_WORKSPACE=saas-<name>
  tfc-admin/            # Codifies the TFC workspace layer (tfe provider) — TF_WORKSPACE=tfc-admin (apply first)

modules/               # grouped by owning cloud (domain)
  gcp/                  # GCP-native modules
    stages/             # Orchestration wrappers: bootstrap, organization, projects, network-hub, workload, host
    project/            # THE project primitive — every stage creates GCP projects through it (no naming scheme inside)
    network/            # ~23 primitives: vpc, subnet, dns, dns-records, vpn, vpc-sc, cloud-armor, internal-lb, api-gateway, cdn, app-ingress, …
    governance/         # billing, kms, org-policy, scc, tags, cloud-audit-logs, private-ca
    iam/                # organization, role, service-account, workload-identity, identity-group*, deny-policy
    monitoring/         # alert-policy, compute-dashboard, slo, control-plane (landing-zone self-observability)
    ops/                # os-config (VM Manager patch deployments)
    backup/             # backup-plan (snapshot schedules)
    compute/            # cloud-run, gke-autopilot (application runtimes)
    data/               # cloud-sql, secret-manager
    firebase/           # project
    cloud-storage/
    artifact-registry/
  aws/                  # AWS-native modules (categorized, mirroring gcp/)
    governance/         # organization, organization-policy, account, cost-governance, service-quotas
    security/           # guardduty-org, securityhub-org, config-org, cloudtrail-org, securitylake, edge-security (CloudFront/WAF), …
    network/            # vpc, transit-gateway, network-firewall, route53-resolver, dns-records, ipam, vpc-endpoints, load-balancer, api-gateway, vpn
    iam/                # iam-role, iam-identity-center, tfc-oidc-baseline
    compute/            # ecs-fargate (application runtime)
    data/               # kms-key, log-archive-bucket, private-ca, ecr, rds-aurora
    backup/             # backup-vault, backup-org-policy
    ops/                # systems-manager, cloudwatch
    stages/             # organization, security, network-hub, shared-services, backup, workload
  supabase/             # project, settings, environment, vault-secrets
  vercel/               # project
  saas/                 # stages/saas-workload — composes supabase + vercel
  tfc/                  # workspace — one Terraform Cloud workspace (used by envs/tfc-admin)
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
| Terraform | `~> 1.11` (CI pins 1.14.3; uses `mock_provider`, `override_module`, `terraform_data`, and write-only `*_wo` arguments so secrets never enter state) |
| google / google-beta | `~> 7.0` (6→7 migration complete; locks on 7.x, CI green — audit L4) |
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
make security       # trivy config + checkov (versions pinned in .tool-versions; tfsec is EOL/removed)
make count          # print live module/root/test-suite counts (make count-check enforces README/CLAUDE.md)
make links          # fail on broken repo-relative Markdown links
make shellcheck     # shellcheck scripts/*.sh
make ci             # fmt-check + consistency + count-check + links + shellcheck + docs-check + validate-all + lint + test + security
```

---

## Testing

- Tests live in each module's `tests/` subdir as `*.tftest.hcl`. Every module ships **at least two** suites: a `variables_validation` suite (input validation via `expect_failures`) **and** at least one plan/behaviour suite that asserts on planned resources — usually named `plan_assertions.tftest.hcl`, occasionally a descriptively named suite (e.g. `budget_filter.tftest.hcl`, `router_bgp.tftest.hcl`).
- `make test` calls `terraform test` with `mock_provider` — **no real cloud credentials needed**.
- Always run `make test` before opening a PR.

---

## State & Apply Rules

- State backend: **Terraform Cloud** (remote).
- **Never run `terraform apply` locally** against any GCP root — `envs/gcp/bootstrap`, `envs/gcp/organization`, `envs/gcp/projects`, `envs/gcp/network-hub` or `envs/gcp/workload` (except the documented phase-0 `gcp-bootstrap` first apply, which runs as a human admin by design). The Makefile `apply-gcp-*` targets deliberately refuse.
- CI (GitHub Actions) runs `fmt`, `docs-check`, `validate` (10 shards), `lint`, Trivy, `checkov`, `test` and meta-lint (yaml/markdown/commits, counts, links) on PR; `Validation Summary` is the single required check.
- Terraform Cloud executes the actual apply.

---

## Required Environment Variables

Only the roots you apply pull in credentials — an unapplied workspace needs none. See [Choosing providers](#choosing-providers).

| Variable | Purpose |
|----------|---------|
| `GOOGLE_CLOUD_PROJECT` / GCP ADC | google provider — GCP roots (`gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub`, `gcp-workload-<env>`) only |
| `TFC_AWS_PROVIDER_AUTH` + `TFC_AWS_PLAN_ROLE_ARN` / `TFC_AWS_APPLY_ROLE_ARN` | AWS via TFC dynamic (OIDC) credentials, per-account `tfc-plan`/`tfc-apply` roles from `modules/aws/iam/tfc-oidc-baseline` (set per workspace by `envs/tfc-admin`; multi-account roots `aws-security`/`aws-backup` also get `TFC_AWS_*_<alias>` per member account) — AWS roots only |
| `TFC_GCP_PROVIDER_AUTH` + `TFC_GCP_WORKLOAD_PROVIDER_NAME` + `TFC_GCP_PLAN/APPLY_SERVICE_ACCOUNT_EMAIL` | GCP via TFC dynamic credentials, per-stage plan/apply SAs from `gcp-bootstrap` (set per workspace by `envs/tfc-admin`) — GCP roots only |
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

### Variable naming: `enable_*` vs `create_*`

Two intentional toggle prefixes — keep them distinct:

- `enable_<feature>` — a **feature gate** (turn a capability on/off, e.g. `enable_cloudwatch_logs`, `enable_vault_secrets`).
- `create_<resource>` — **resource ownership** (does this module create the resource, or is an existing one passed in, e.g. `create_health_check`, `create_router`).

Do not introduce a third `use_*`/`with_*` variant. Keep variable descriptions free of internal provenance codes; open/preview/deferred items live in [`docs/known-gaps.md`](docs/known-gaps.md), not in `description` strings.

### Sensitive values in `terraform_data` / `null_resource` triggers

Terraform rejects raw sensitive values in triggers. Always hash them (and prefer write-only `*_wo` arguments over storing secrets at all):

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

`modules/supabase/vault-secrets` installs its Node.js dependencies **automatically** at apply time: a `terraform_data.npm_install` runs `npm ci --ignore-scripts --no-audit --no-fund --prefix modules/supabase/vault-secrets/scripts` before the bootstrap/reconcile provisioners (which `import { Pool } from "pg"`). No manual step — the apply runner just needs **Node.js 18+ and npm** on PATH. To prime locally: `npm ci --ignore-scripts --prefix modules/supabase/vault-secrets/scripts`. The vault RPCs live in the unexposed `iac_vault` schema (never in `public`).

### AWS modules

Gotchas the AWS landing-zone build surfaced — each one bit us in CI:

1. **Pin `aws = ">= 6.46.0, < 7.0.0"`** — NOT a bare `~> 6.0`. The plan uses resources added mid-6.x; an older 6.x provider fails to plan.
2. **Cross-account modules declare `configuration_aliases`** and therefore CANNOT be root-`terraform validate`d standalone. The CI validate step skips them; they are covered by `examples/`, the composing roots, and `mock_provider` tests instead.
3. **Build policy JSON with `jsonencode()` / `templatefile()`**, NOT `data "aws_iam_policy_document"`. `mock_provider` mocks data sources, which breaks content assertions in tests.
4. **`regex()` interval repeats cap at 1000** (RE2 engine) — a larger `{n,m}` repeat count is a plan-time error.
5. **Log-service KMS grants must use per-service-principal statements**, NOT `kms:ViaService` — `kms:ViaService` would deny CloudTrail. (The CloudTrail grant's `aws:SourceOrgID`-vs-`aws:SourceArn` condition is an open, unvalidated item — tracked in [`docs/known-gaps.md`](docs/known-gaps.md#open--validate-before-relying-on), not here.)
6. **Commit multi-platform `.terraform.lock.hcl`** so CI (Linux) and local macOS resolve the same provider hashes: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64`. Note: many committed lockfiles currently hold only the `darwin_arm64` `h1:` hash (written by a local `terraform init`); regenerate with the command above when you touch one.

---

## Navigating the Codebase

| Goal | Where to look |
|------|--------------|
| Org-level GCP resources | `envs/gcp/organization/` |
| Per-env app infra | `envs/gcp/workload/` (set `TF_WORKSPACE=gcp-workload-<env>`) |
| Full end-to-end workload | `modules/gcp/stages/workload/` or `modules/saas/stages/saas-workload/` |
| VPC / networking | `modules/gcp/network/` |
| IAM / service accounts | `modules/gcp/iam/` |
| KMS / billing / org policy | `modules/gcp/governance/` |
| Supabase integration | `modules/supabase/` |
| Vercel integration | `modules/vercel/` |
| Alerts / dashboards | `modules/gcp/monitoring/` |
| AWS org / guardrails | `envs/aws/organization/` + `modules/aws/stages/organization/` |
| AWS security baseline | `envs/aws/security/` + `modules/aws/stages/security/` |
| AWS network hub | `envs/aws/network/` + `modules/aws/stages/network-hub/` |
| AWS IAM Identity Center | `envs/aws/identity/` |
| AWS backup | `envs/aws/backup/` + `modules/aws/stages/backup/` |
| AWS workloads | `envs/aws/workload/` (set `TF_WORKSPACE=aws-workload-<env>`) |
| AWS modules | `modules/aws/` |
| SaaS-only (Supabase/Vercel) | `envs/saas/` |
| AWS architecture | `docs/architecture/aws-landing-zone.md` |

---

## Common Workflows

### Adding a new module

1. Create `modules/<category>/<name>/`.
2. Add `main.tf`, `variables.tf`, `outputs.tf`.
3. Add README with `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers.
4. Add a `*.tftest.hcl` with at least one `mock_provider` test.
5. Run `make docs && make test && make ci`.

For **AWS modules**, clone `templates/aws/module/` instead — it pins `aws = ">= 6.46.0, < 7.0.0"` and ships a `mock_provider "aws"` test. Cross-account modules declare `configuration_aliases` (see [Module Authoring Rules → AWS modules](#aws-modules)).

### Updating an existing module

1. Edit the module.
2. Run `make docs` to regenerate the README section.
3. Run `make test` to verify.
4. Run `make ci` before pushing.

### Working with environments

```bash
# Target a specific app environment
export TF_WORKSPACE=gcp-workload-staging
cd envs/gcp/workload
terraform plan   # read-only local check — apply only via TFC
```

### Standing up the AWS landing zone

Follow [`docs/runbooks/aws-bootstrap.md`](docs/runbooks/aws-bootstrap.md): run phase-0 (out-of-band org creation → a runnable `aws-organization` workspace), apply `aws-organization`, enable/delegate IAM Identity Center, then apply the remaining layers in order (`aws-security` → `aws-network` → `aws-identity` → `aws-shared-services` → `aws-backup` → `aws-workload`). Ordering is enforced by apply order + remote-state reads, not cross-root `depends_on`.

### Adding an AWS account / workload

Follow [`docs/runbooks/aws-add-account.md`](docs/runbooks/aws-add-account.md): add the account to the org map, apply `aws-organization`, create the TFC workspace and wire its run role, then apply the workload layer (`TF_WORKSPACE=aws-workload-<env>`).
