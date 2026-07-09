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

One root per cloud + layer, named `envs/<cloud>-<layer>`. Each root declares exactly the provider(s) it needs and nothing else. A run of that root only ever requires that cloud's credentials.

### Root inventory

| Root | Workspace | Cloud | Status |
|---|---|---|---|
| `envs/organization` | `organization` | GCP (control plane) | existing |
| `envs/apps` | `apps-<env>` | GCP (per-env app infra) | existing |
| `envs/aws-organization` | `aws-organization` | AWS (foundational accounts + org) | AWS |
| `envs/aws-security` | `aws-security` | AWS (security tooling / log archive) | AWS |
| `envs/aws-network` | `aws-network` | AWS (shared networking) | AWS |
| `envs/aws-identity` | `aws-identity` | AWS (IAM Identity Center / SSO) | AWS |
| `envs/aws-shared-services` | `aws-shared-services` | AWS (shared platform services) | AWS |
| `envs/aws-backup` | `aws-backup` | AWS (centralized backup) | AWS |
| `envs/aws-workload` | `aws-workload-<env>` | AWS (per-env workloads) | AWS |
| `envs/saas` | `saas-<name>` | Supabase and/or Vercel only | SaaS |

The GCP roots (`organization`, `apps`) are the existing landing zone. The AWS roots follow the standard multi-account foundational layout. The `saas` root is the **only** place Supabase and Vercel providers live — they never live inside an AWS or GCP root.

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
| GCP only | `organization`, `apps-<env>` | GCP ADC |
| AWS only (baseline) | `aws-organization`, `aws-security` (+ `aws-network`/`aws-identity`/`aws-backup`/`aws-workload-<env>` as needed) | AWS (management + assume-role) |
| Supabase only | `saas` with `enable_supabase=true, enable_vercel=false` | `SUPABASE_ACCESS_TOKEN` |
| Vercel only | `saas` with `enable_vercel=true, enable_supabase=false` | `VERCEL_API_TOKEN` |
| Supabase + Vercel | `saas` with both true | both SaaS tokens |
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
- The `saas` root needs only the SaaS token(s) for the features you enable — and SaaS never lives inside an AWS or GCP root.

So the credentials a deployment needs are exactly the union of the credentials of the roots you apply. There is no hidden cross-cloud coupling, and there is no top-level `enable_aws` / `enable_gcp` switch — selection is purely which workspaces you run.

---

## Cross-cloud wiring via remote state

Roots that need a value from another root read it with `terraform_remote_state` against the `cloud` backend. This is how the `saas` root can consume, say, a DNS zone name or a project ID emitted by a GCP or AWS root without ever configuring that cloud's provider.

Critically, the lookup resolves at **plan time from state** and needs **no cloud credentials** — only the TFC organization, supplied as a variable:

```hcl
data "terraform_remote_state" "gcp_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "organization"
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
- `scripts/terraform-roots.sh` — enumerates every root (any `envs/<dir>` containing a `.tf` file) plus modules and examples. CI's validate/lint/fmt matrix is driven from this, so a new `envs/<cloud>-<layer>` is picked up the moment it lands.
