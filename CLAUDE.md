# CLAUDE.md — Agent Onboarding

Terraform GCP + AWS landing zone. 89 modules, 10 deployable roots, remote state via Terraform Cloud.

---

## Repo Layout

```text
envs/                   # deployable roots, nested by cloud (workspace names keep the flat gcp-/aws- form)
  gcp/
    organization/       # GCP control plane: folders, org policies, KMS, network hub, bootstrap WIF
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

modules/               # grouped by owning cloud (domain)
  gcp/                  # GCP-native modules
    stages/             # Orchestration wrappers: bootstrap, organization, projects, network-hub, workload, host
    network/            # ~19 primitives: vpc, subnet, dns, vpn, vpc-sc, cloud-armor, …
    governance/         # billing, kms, org-policy, scc, tags, cloud-audit-logs
    iam/                # organization, role, service-account, workload-identity, identity-group*
    monitoring/         # alert-policy, compute-dashboard
    firebase/           # project
    cloud-storage/
    artifact-registry/
  aws/                  # AWS-native modules (categorized, mirroring gcp/)
    governance/         # organization, organization-policy, account, cost-governance, service-quotas
    security/           # guardduty-org, securityhub-org, config-org, cloudtrail-org, securitylake, …
    network/            # vpc, transit-gateway, network-firewall, route53-resolver, ipam, vpc-endpoints
    iam/                # iam-role, iam-identity-center
    data/               # kms-key, log-archive-bucket, private-ca
    backup/             # backup-vault, backup-org-policy
    ops/                # systems-manager
    stages/             # organization, security, network-hub, shared-services, backup, workload
  supabase/             # project, settings, environment, vault-secrets
  vercel/               # project
  saas/                 # stages/saas-workload — composes supabase + vercel
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
| google / google-beta | `>= 6.0, < 8.0` (spans the in-progress 6→7 migration; locks are on 7.x, CI green. Finish the migration + tighten to `~> 7.0` as a follow-up.) |
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

- Tests live in each module's `tests/` subdir as `*.tftest.hcl` (2 per module: `variables_validation` + `plan_assertions`).
- `make test` calls `terraform test` with `mock_provider` — **no real cloud credentials needed**.
- Always run `make test` before opening a PR.

---

## State & Apply Rules

- State backend: **Terraform Cloud** (remote).
- **Never run `terraform apply` locally** against `envs/gcp/organization` or `envs/gcp/workload`.
- CI (GitHub Actions) runs `fmt`, `validate`, `lint`, `tfsec`, `checkov` on PR.
- Terraform Cloud executes the actual apply.

---

## Required Environment Variables

Only the roots you apply pull in credentials — an unapplied workspace needs none. See [Choosing providers](#choosing-providers).

| Variable | Purpose |
|----------|---------|
| `GOOGLE_CLOUD_PROJECT` / GCP ADC | google provider — GCP roots (`gcp-organization`, `gcp-workload`) only |
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

`modules/supabase/vault-secrets` installs its Node.js dependencies **automatically** at apply time: a `null_resource.npm_install` runs `npm ci --prefix modules/supabase/vault-secrets/scripts` before the bootstrap/reconcile provisioners (which `import { Pool } from "pg"`). No manual step — the apply runner just needs **Node.js 18+ and npm** on PATH. To prime locally: `npm ci --prefix modules/supabase/vault-secrets/scripts`.

### AWS modules

Gotchas the AWS landing-zone build surfaced — each one bit us in CI:

1. **Pin `aws = ">= 6.46.0, < 7.0.0"`** — NOT a bare `~> 6.0`. The plan uses resources added mid-6.x; an older 6.x provider fails to plan.
2. **Cross-account modules declare `configuration_aliases`** and therefore CANNOT be root-`terraform validate`d standalone. The CI validate step skips them; they are covered by `examples/`, the composing roots, and `mock_provider` tests instead.
3. **Build policy JSON with `jsonencode()` / `templatefile()`**, NOT `data "aws_iam_policy_document"`. `mock_provider` mocks data sources, which breaks content assertions in tests.
4. **`regex()` interval repeats cap at 1000** (RE2 engine) — a larger `{n,m}` repeat count is a plan-time error.
5. **Log-service KMS grants must use per-service-principal statements**, NOT `kms:ViaService` — `kms:ViaService` would deny CloudTrail. **⚠️ Open (audit A1, unvalidated):** the CloudTrail grant in `modules/aws/data/kms-key` currently scopes with `aws:SourceOrgID`, but AWS documents `aws:SourceArn` (the trail ARN) as the KMS-key-policy condition for CloudTrail — `aws:SourceOrgID` is documented for the S3 *bucket* policy, not KMS key policies. If CloudTrail does not populate `aws:SourceOrgID` on its KMS calls, log delivery fails. This has only been `mock_provider`-tested; **validate against a real org and switch CloudTrail to `aws:SourceArn` before relying on it.** See [AWS: KMS key policy for CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-kms-key-policy-for-cloudtrail.html).
6. **Commit dual-platform `.terraform.lock.hcl`** (`linux_amd64` + `darwin_amd64`) so both CI runners and local macOS resolve the same provider hashes.

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
