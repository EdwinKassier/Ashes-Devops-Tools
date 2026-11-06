# GCP Control-Plane State Decomposition (audit H3)

> **Status: implemented.** All four control-plane roots now exist and are split
> into separate states: `gcp-bootstrap`, `gcp-organization`, `gcp-projects`,
> `gcp-network-hub` (plus `gcp-workload-<env>`). Each has an
> `envs/gcp/<root>/tests/root.tftest.hcl` contract test, and all roots `terraform validate`. The design below is retained
> for the rationale and for the cross-STATE migration procedure that an
> already-deployed organization needs (this repo is never-applied, so no
> migration was required here).

## Problem

`envs/gcp/organization` composes **four** stage modules in one state and one TFC
workspace: `bootstrap` + `organization` + `projects` + `network-hub`
(`envs/gcp/organization/main.tf`). That single `gcp-organization` state owns the
admin project, the Terraform service account, GitHub/TFC WIF, folders, org
policy, KMS, audit logging, billing, the hub VPC, and **every host project for
every environment**.

The AWS side is properly layered (org → security → network → identity →
shared-services → backup → workload). The GCP side is not. One bad apply, state
corruption, or lock loss on `gcp-organization` can take out the control plane for
prod, uat, and dev at once. This is below Google's enterprise-foundations
blueprint, which splits 0-bootstrap / 1-org / 2-environments / 3-networks /
4-projects into separate states precisely to shrink that blast radius.

## Target decomposition

Split `gcp-organization` along the same seams AWS and the Google blueprint use.
The stage modules already exist and are independently tested, so this is a
root/workspace restructuring, not new module code.

| New root | Workspace | Stage(s) | Reads (remote state) | Produces |
|---|---|---|---|---|
| `envs/gcp/bootstrap` | `gcp-bootstrap` | `stages/bootstrap` | none (phase-0) | admin project id, Terraform SA, WIF pool/provider |
| `envs/gcp/organization` (slimmed) | `gcp-organization` | `stages/organization` | `gcp-bootstrap` | org id, folders, KMS keys, billing, audit sink |
| `envs/gcp/projects` | `gcp-projects` | `stages/projects` | `gcp-organization` | per-env host project ids |
| `envs/gcp/network-hub` | `gcp-network-hub` | `stages/network-hub` | `gcp-projects`, `gcp-organization` | hub VPC, VPC-SC perimeter |
| `envs/gcp/workload` (unchanged) | `gcp-workload-<env>` | `stages/workload` | `gcp-network-hub`, `gcp-projects` | per-env workload infra |

Ordering is enforced by apply order plus remote-state reads, exactly as on AWS
(no cross-root `depends_on`). Each new root gets its own `backend.tf`
(a `cloud {}` block with `name = "gcp-..."`), `providers.tf`, `variables.tf`, `outputs.tf`, and a
`envs/gcp/<root>/tests/root.tftest.hcl` contract test mirroring
`envs/aws/*/tests/root.tftest.hcl`.

## Dependency contract

Each upstream root publishes a stable output set (the same "keep stable" rule the
AWS roots use). Add a cross-root output-contract test per producer (see the
pattern now in `envs/aws/organization/tests/root.tftest.hcl`) so a renamed output
fails in CI rather than at a downstream apply.

## Migration

- **This repo (never applied):** no state migration is needed. Create the new
  root directories, move each stage module instantiation and its variables into
  the matching root, wire the remote-state reads, add backends and contract
  tests, and update the bootstrap runbook's apply order.
- **An already-deployed org:** the resources currently live in one state. Moving
  them requires `terraform state mv` into the new states (or `removed` +
  `import`), per stage, in a maintenance window, lowest-dependency first
  (bootstrap, then organization, then projects, then network-hub). Plan each move
  as no-op before applying.

## First slice (highest value, lowest risk): extract `bootstrap`

Do bootstrap first. It holds the WIF and Terraform SA that everything else
depends on, it is phase-0 in the runbook, and it is the most dangerous to
co-locate with per-environment project state.

1. Create `envs/gcp/bootstrap/` with `backend.tf` (`cloud { workspaces { name = "gcp-bootstrap" } }`),
   `providers.tf`, `main.tf` (instantiating only `stages/bootstrap`),
   `variables.tf`, `outputs.tf` (admin project id, Terraform SA email, WIF pool
   and provider ids), and `envs/gcp/bootstrap/tests/root.tftest.hcl`.
2. Remove the `bootstrap` stage from `envs/gcp/organization/main.tf`; replace its
   in-state references with a `data "terraform_remote_state" "gcp_bootstrap"`
   read.
3. Update `docs/runbooks/bootstrap.md`: `gcp-bootstrap` is applied before
   `gcp-organization`, and its TFC workspace is created in phase-0.
4. `terraform validate` + `terraform test` both roots; confirm the contract test
   passes.

The remaining splits (`projects`, `network-hub`) follow the same pattern and can
land as separate PRs. Each is independently reviewable, which is the point: a
state-topology change should not ride along with unrelated edits.
