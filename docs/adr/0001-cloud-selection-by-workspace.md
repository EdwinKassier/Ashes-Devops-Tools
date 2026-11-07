# ADR 0001: Cloud selection is which workspaces you apply

- Status: Accepted
- Date: 2026-11-07

## Context

A `provider` block cannot be conditional, and Terraform configures and authenticates any provider referenced in a configuration, even on resources with `count = 0`. A runtime `enable_<cloud>` flag therefore cannot make a cloud optional: the root would still need that cloud's credentials. The repo must support any combination of `{aws, gcp, supabase, vercel}` ([provider selection](../architecture/provider-selection.md)).

## Decision

Each cloud has its own deployable roots under `envs/` and its own HCP Terraform workspaces. Choosing clouds means choosing which workspaces exist and are applied; `config/landing-zone.yaml` declares this (`<cloud>.enabled`) and `envs/tfc-admin` derives the workspaces from it. `enable_*` flags only gate features inside a root (`enable_supabase`, `enable_vercel`, `enable_edge`).

## Consequences

- An unused cloud's provider is physically absent from the roots that are applied, so it needs no credentials.
- More roots and workspaces than a single-root design: 15 deployable roots.
- Cross-cloud wiring happens through published outputs and opt-in seams, not shared state (see ADR 0003 and ADR 0008).
