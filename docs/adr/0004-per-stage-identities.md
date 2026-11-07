# ADR 0004: Per-stage plan and apply identities

- Status: Accepted
- Date: 2026-11-07

## Context

One automation identity for every stage means a speculative plan on a pull request holds the same power as an apply, and a compromise of any stage reaches the whole estate.

## Decision

Each stage gets a read-only plan identity and a least-privilege apply identity, bound to the HCP workspace and run phase. On GCP, `gcp-bootstrap` creates `<prefix>-<stage>-plan` and `<prefix>-<stage>-apply` service accounts, and each environment gets `<prefix>-wl-<env>-plan|apply` with no org-level roles; WIF bindings key on `workspace:run_phase`. On AWS, `modules/aws/iam/tfc-oidc-baseline` creates `tfc-plan` and `tfc-apply` roles per member account, each trusting only its workspace and `run_phase` subject. `envs/tfc-admin` sets the matching `TFC_*` variables per workspace.

## Consequences

- A plan never receives write credentials. AWS IAM can condition only on a few OIDC claims, so trust is by workspace name, which makes workspace names security-relevant.
- Many identities to provision; tfc-admin automates it.
- The AWS apply role is still broad (see ADR 0007).
