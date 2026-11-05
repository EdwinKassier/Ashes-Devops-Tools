# SaaS Integration: Options and Decision (audit H9)

**Status:** Decided — **Option C (hybrid, opt-in seams)**. Secret bridge delivered
for both clouds (`enable_saas_secret_bridge` on `envs/gcp/workload` and
`envs/aws/workload`), and the frontend-URL seam delivered (`cross_cloud_references`
on `envs/saas`). Remaining increment: DNS unification.

**Audit finding (H9):** the SaaS tier (Supabase and Vercel) is a disconnected
island. `modules/saas/stages/saas-workload` composes the SaaS modules, but no
AWS or GCP root consumes SaaS state and no SaaS root consumes cloud state. The
integration story is undecided, so the pieces do not form a product.

---

## Current state

- `envs/saas` is a credential-free root: it declares no `aws`/`google` provider,
  so applying `saas-<name>` pulls in no cloud credentials. `enable_supabase`,
  `enable_vercel`, and `enable_vault_secrets` gate the three features
  independently.
- The SaaS root exposes outputs: `supabase_api_url`, `supabase_anon_key`,
  `supabase_service_role_key` (sensitive), `supabase_database_password`
  (sensitive), and `vercel_project_id`.
- One integration seam exists, but it is **commented out** in `envs/saas/main.tf`
  (Convention 5): a SaaS root can read an upstream cloud output via
  `terraform_remote_state` and feed it into a Vercel env var or Supabase input
  (for example, give the Vercel frontend the backend's API URL). It reads from
  state, so it needs no AWS or GCP credentials.
- The reverse direction is not built: nothing in a cloud root reads the SaaS
  outputs, so a GCP or AWS runtime cannot use Supabase as its datastore today.

### Constraint that shapes the options

Supabase's standard tier is internet-only: it does not peer into a VPC. So
"integration" cannot mean private network attachment. The realistic seams are:

1. **Frontend to backend URL:** the Vercel app learns the cloud runtime's public
   API endpoint. (The half-built seam above.)
2. **Secrets:** a cloud runtime learns Supabase's connection string and keys from
   its own secret store (`modules/gcp/data/secret-manager` or AWS Secrets
   Manager), so Supabase can act as a managed datastore behind the runtime.
3. **DNS:** Vercel and Supabase custom domains sit under the org's managed zone
   (Cloud DNS or Route 53) instead of a separate registrar.

---

## The options

| | A. Standalone track | B. Fully integrated tier | C. Hybrid, opt-in seams |
|---|---|---|---|
| SaaS role | Independent product surface | Primary datastore and frontend behind the cloud runtime | Either, per flag |
| Frontend URL seam | Documented, kept optional | Required | Opt-in |
| Secret bridge (Supabase to cloud) | None | Required | Opt-in |
| DNS unification | Out of scope | Required | Opt-in |
| Cross-root coupling | None | SaaS and cloud roots depend on each other's state | One-directional, guarded, optional |
| Effort | Low | High | Medium |
| Fits | Teams running Supabase/Vercel as a standalone product | A single integrated app where Supabase is the system of record | The repo's "any combination, opt-in" philosophy |

### Option A: standalone track

Declare SaaS an explicitly independent tier. Keep the one-directional frontend
seam as the only coupling, document it as supported, and state plainly that
Supabase/Vercel are not wired into the cloud tier.

- **Build:** turn the commented seam into a small, uncomment-free helper (a
  `cross_cloud_references` variable that maps an upstream workspace output to a
  Vercel/Supabase env var), plus a short "SaaS as a standalone track" doc.
- **Pro:** lowest effort and risk; no cross-root ordering; honours the
  credential-free SaaS root.
- **Con:** does not answer "can Supabase be the datastore behind my GCP/AWS
  runtime"; the answer stays "no, run it separately".

### Option B: fully integrated tier

Make Supabase the system of record behind the cloud runtime and unify DNS.

- **Build:** a secret bridge that writes the Supabase outputs
  (`database_password`, `service_role_key`, `api_url`) into GCP Secret Manager or
  AWS Secrets Manager, so the runtime reads them by reference; DNS records for the
  Vercel and Supabase custom domains in the managed zone; the frontend URL seam,
  required. This introduces a hard ordering (SaaS before the consuming cloud root,
  or a two-phase apply) and cross-root state reads in both directions.
- **Pro:** one coherent application; Supabase and the cloud runtime are one
  system.
- **Con:** highest effort; coupples the SaaS and cloud lifecycles; weakens the
  "any combination" property, since the cloud runtime now depends on the SaaS
  root; sensitive SaaS values transit a second state file.

### Option C: hybrid, opt-in seams (recommended)

Keep SaaS independently deployable, and add each integration as an opt-in,
one-directional seam that is off by default. Nothing is forced; integration is
config.

- **Build, incrementally:**
  1. **Secret bridge (opt-in) — DELIVERED for GCP and AWS.**
     `enable_saas_secret_bridge` reads the `saas-<name>` remote state and writes
     the Supabase connection details into the cloud's secret store: GCP Secret
     Manager on `envs/gcp/workload` (reusing `modules/gcp/data/secret-manager`),
     and AWS Secrets Manager on `envs/aws/workload` (granting named task roles
     GetSecretValue). Default off on both.
  2. **Frontend-URL seam — DELIVERED.** `cross_cloud_references` on `envs/saas`
     resolves an upstream AWS/GCP workspace output (for example a runtime's API
     endpoint) from remote state and injects it as a Vercel shared env var, so the
     frontend learns the backend URL. No cloud credentials, only tfc_organization.
     Default empty: the root stays standalone.
  3. **DNS (opt-in):** let the managed DNS zone optionally hold the Vercel and
     Supabase custom-domain records. Not yet built.
- **Pro:** matches the repo's provider-selection philosophy (deploy any
  combination, opt in per feature); keeps the SaaS root credential-free; each
  seam is independently testable and reversible.
- **Con:** more moving parts than A; the owner must still decide which seams to
  turn on per environment.

---

## Recommendation

**Option C.** The repo's whole design is "deploy any combination, opt-in, admin
in control" (see [provider-selection.md](provider-selection.md)). A hybrid set of
opt-in seams extends that philosophy to SaaS: a team can run Supabase and Vercel
standalone, or place Supabase behind a GCP/AWS runtime, by flipping a flag, not by
re-architecting. It avoids Option B's hard cross-root coupling while still
answering "yes, Supabase can be my datastore" for teams that want it.

Suggested first increment if C is chosen: the **secret bridge**, because it
unlocks the most-requested integration (Supabase as the datastore behind the
runtime) and reuses `modules/gcp/data/secret-manager` and AWS Secrets Manager,
which already exist. The frontend URL seam and DNS can follow.

## What this decision does not change

Whichever option is chosen, the SaaS root stays credential-free and the three
feature flags stay independent. Integration is additive; it never makes SaaS a
precondition for a cloud-only or a SaaS-only deployment.
