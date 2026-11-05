# Provider Selection

The headline feature of this platform: you can deploy **any combination** of the four supported clouds — `{aws, gcp, supabase, vercel}` — because each cloud lives in its own root (and therefore its own Terraform Cloud workspace). An unused cloud's provider is **physically absent** from the roots you apply, so it is never configured and never authenticated.

This document explains the constraint that forces the design, the per-cloud-root model, and the full combination matrix.

---

## The Terraform constraint that forces the design

A `provider "x" {}` block **cannot be made conditional**. There is no `count` or `for_each` on a provider block. Worse, Terraform configures **and authenticates** any provider that is referenced by any resource in the configuration — **even when that resource has `count = 0`**. Setting an `enable_<cloud>` flag to `false` does not prevent the provider from initializing; the block is still present, still evaluated, and still requires valid credentials at plan time.

This is documented behavior, not a bug we can work around:

- <https://github.com/hashicorp/terraform/issues/31662>
- <https://github.com/hashicorp/terraform-provider-aws/issues/38039>

The practical consequence: **you cannot make a cloud optional with a runtime flag inside a single root.** If a root declares `provider "aws"`, every plan/apply of that root needs AWS credentials, whether or not any AWS resource is actually created.

The only way to make a cloud genuinely optional is to make its provider **absent** from the configuration you run. That means a separate deployable root — and therefore a separate TFC workspace — per cloud per layer.

**Cloud selection is which workspaces you apply, not a runtime `enable_<cloud>` flag.** A workspace that is never applied costs nothing and pulls in no credentials.

`enable_*` flags still exist, but they only gate **features within a root** — for example `enable_supabase`, `enable_vercel`, `enable_edge`. They never turn a whole cloud on or off.

---

## The per-cloud-root model

One root per cloud + layer, named `envs/<cloud>/<layer>`. Each root declares exactly the provider(s) it needs and nothing else. A run of that root only ever requires that cloud's credentials.

### Root inventory

| Root | Workspace | Cloud | Status |
|---|---|---|---|
| `envs/gcp/bootstrap` | `gcp-bootstrap` | GCP (phase-0 automation foundation) | existing |
| `envs/gcp/organization` | `gcp-organization` | GCP (org policy, KMS, audit, billing) | existing |
| `envs/gcp/projects` | `gcp-projects` | GCP (host/spoke projects) | existing |
| `envs/gcp/network-hub` | `gcp-network-hub` | GCP (hub VPC, DNS, VPC-SC) | existing |
| `envs/gcp/workload` | `gcp-workload-<env>` | GCP (per-env app infra) | existing |
| `envs/aws/organization` | `aws-organization` | AWS (foundational accounts + org) | AWS |
| `envs/aws/security` | `aws-security` | AWS (security tooling / log archive) | AWS |
| `envs/aws/network` | `aws-network` | AWS (shared networking) | AWS |
| `envs/aws/identity` | `aws-identity` | AWS (IAM Identity Center / SSO) | AWS |
| `envs/aws/shared-services` | `aws-shared-services` | AWS (shared platform services) | AWS |
| `envs/aws/backup` | `aws-backup` | AWS (centralized backup) | AWS |
| `envs/aws/workload` | `aws-workload-<env>` | AWS (per-env workloads) | AWS |
| `envs/saas` | `saas-<name>` (via `TF_WORKSPACE=saas-<name>`) | Supabase and/or Vercel only | SaaS |

The GCP roots (`gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub`, `gcp-workload`, applied in that order) are the existing landing zone. The AWS roots follow the standard multi-account foundational layout. The `saas` root is the **only** place Supabase and Vercel providers live — they never live inside an AWS or GCP root. It declares **no `aws` or `google` provider at all**, so a Supabase- and/or Vercel-only user needs no cloud credentials to plan or apply it. Its `enable_supabase` / `enable_vercel` flags gate the two SaaS features independently within the single root.

### Minimum AWS footprint

The minimum governed, monitored AWS baseline is:

```text
aws-organization   # foundational accounts + org structure
aws-security       # security tooling, log archive, guardrails
```

Everything else is **additive** — `aws-network`, `aws-identity`, `aws-shared-services`, `aws-backup`, and `aws-workload-<env>` are applied only when you need them. You never have to apply a root you don't want.

---

## The combination matrix

Pick what you want; apply exactly those workspaces. Credentials come from the roots you actually apply — never from roots you leave unapplied.

| You want… | Apply these workspaces | Credentials required |
|---|---|---|
| GCP only | `gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub`, `gcp-workload-<env>` | GCP ADC |
| AWS only (baseline) | `aws-organization`, `aws-security` (+ `aws-network`/`aws-identity`/`aws-backup`/`aws-workload-<env>` as needed) | AWS (management + assume-role) |
| Supabase only | `saas-<name>` with `enable_supabase=true, enable_vercel=false` | `SUPABASE_ACCESS_TOKEN` only (no aws/google provider in the root) |
| Vercel only | `saas-<name>` with `enable_vercel=true, enable_supabase=false` | `VERCEL_API_TOKEN` only (no aws/google provider in the root) |
| Supabase + Vercel | `saas-<name>` with both true | `SUPABASE_ACCESS_TOKEN` + `VERCEL_API_TOKEN` (still no aws/google provider) |
| AWS + GCP | AWS set + GCP set | AWS + GCP |
| GCP + SaaS | GCP set + `saas` | GCP + SaaS token(s) |
| AWS + SaaS | AWS set + `saas` | AWS + SaaS token(s) |
| AWS + GCP + SaaS | all of the above | all relevant |
| any other subset | the union of the per-cloud rows above | union of the per-cloud creds |

---

## Why every subset works

The four clouds are **four independent axes**: `aws`, `gcp`, `supabase`, `vercel`. Their combinations form a power set of `2^4 = 16` subsets (including the empty set — deploy nothing). Every non-trivial subset in the matrix above is simply the **union of the single-cloud rows**.

This composes cleanly because **no root forces another cloud's credentials**:

- The GCP roots need only GCP ADC.
- The AWS roots need only AWS credentials.
- The `saas` root needs only the SaaS token(s) for the features you enable — and SaaS never lives inside an AWS or GCP root. (Within that one root, see [Single-provider mode in the `saas` root](#single-provider-mode-in-the-saas-root) for how the disabled SaaS provider avoids needing its token.)

So the credentials a deployment needs are exactly the union of the credentials of the roots you apply. There is no hidden cross-cloud coupling, and there is no top-level `enable_aws` / `enable_gcp` switch — selection is purely which workspaces you run.

---

## Single-provider mode in the `saas` root

`envs/saas` declares both the `supabase` and `vercel` providers, because a `provider` block cannot be conditional. Terraform configures **every** provider a root declares, even when all of its resources are at `count = 0`. Both providers fail at configure time when their token is empty (`Missing Supabase API Access Token` and `Unable to find api_token`), so until 2026-11 a Supabase-only plan demanded `VERCEL_API_TOKEN` and the reverse was also true. The 2026-11-05 audit verified this.

**Fix: an inert placeholder token for the disabled provider** (`envs/saas/providers.tf`):

```hcl
provider "supabase" {
  access_token = var.enable_supabase ? null : local.supabase_disabled_placeholder_token
}

provider "vercel" {
  api_token = var.enable_vercel ? null : local.vercel_disabled_placeholder_token
}
```

- **Enabled:** the attribute is `null`, so the provider reads `SUPABASE_ACCESS_TOKEN` / `VERCEL_API_TOKEN` from the environment exactly as before.
- **Disabled:** the provider gets a format-valid placeholder (`sbp_` + 40 zeros, or 24 zeros). Neither provider calls its API while configuring, and with the feature off no resource or data source uses it, so the placeholder is never sent anywhere. It is not a credential. Provider configuration takes precedence over the environment, so a stray token in the environment is ignored for the disabled provider.

**Evidence** (2026-11-05, `supabase/supabase` 1.9.1, `vercel/vercel` 4.8.2, Terraform 1.14). A real `terraform plan` ran against a local-backend copy of the root with both token variables unset, not under `mock_provider`:

| Mode | Environment | Before | After |
|---|---|---|---|
| Supabase only | `SUPABASE_ACCESS_TOKEN` only | `Error: Unable to find api_token` (vercel) | `Plan: 2 to add` |
| Vercel only | `VERCEL_API_TOKEN` only | `Error: Missing Supabase API Access Token` | `Plan: 7 to add` |
| Supabase only | no tokens | error | error for **supabase only** (the enabled provider) |
| Vercel only | no tokens | error | error for **vercel only** (the enabled provider) |
| Neither | no tokens | error | plans (outputs only) |

Regression tests: `envs/saas/tests/single_provider_supabase_only.tftest.hcl` and `single_provider_vercel_only.tftest.hcl` mock **only the enabled** provider. The disabled provider is the real plugin, configured by `providers.tf`. Both tests fail against the old `providers.tf` and pass now. They need no credentials or network.

**Caveat: turning a feature off after it has been applied.** If the disabled provider's resources are still in state, Terraform refreshes and destroys them with the placeholder token. That fails with an auth error, which is fail-closed: nothing is changed. Destroy them first with the feature still enabled (for example `terraform destroy -target=module.saas_workload.module.vercel_project`), then flip the flag.

A split into separate `saas-supabase` / `saas-vercel` roots was considered and is not needed: the placeholder keeps one root, one workspace and the cross-SaaS wiring (Supabase outputs feeding Vercel env vars) intact.

---

## Cross-cloud wiring via remote state

Roots that need a value from another root read it with `terraform_remote_state` against the `cloud` backend. This is how the `saas` root can consume, say, a DNS zone name or a project ID emitted by a GCP or AWS root without ever configuring that cloud's provider.

How far to take SaaS-to-cloud integration (standalone, fully integrated, or hybrid opt-in seams) is a scoped decision: see [saas-integration.md](saas-integration.md).

Critically, the lookup resolves at **plan time from state** and needs **no cloud credentials** — only the TFC organization, supplied as a variable:

```hcl
data "terraform_remote_state" "gcp_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "gcp-organization"
    }
  }
}
```

- `organization` always comes from `var.tfc_organization` — never hard-coded, so the same root works across TFC orgs.
- `workspaces = { name = ... }` targets the upstream root's workspace by name.
- Because this reads state (not the live cloud API), a downstream root passes `terraform validate -backend=false` with **no** upstream-cloud credentials — which is exactly what the PR validation workflow does.

See [`docs/architecture/adding-a-cloud.md`](adding-a-cloud.md) for the full cross-root contract (stable output keys, aliased foundational providers, the scaffold templates).

---

## Discovery

Nothing hard-codes the root list. Two scripts derive it:

- `scripts/active-providers.sh` — lists which provider each root declares, so you can see which clouds are actually configured and therefore which credentials a run needs. *(Added in Task A4.)*
- `scripts/terraform-roots.sh` — enumerates every root (any `envs/<dir>` containing a `.tf` file) plus modules and examples. CI's validate/lint/fmt matrix is driven from this, so a new `envs/<cloud>/<layer>` is picked up the moment it lands.
