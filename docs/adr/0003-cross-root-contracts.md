# ADR 0003: Cross-root contracts

- Status: Accepted
- Date: 2026-11-07

## Context

Roots read each other through `terraform_remote_state` and `tfe_outputs`. Reading individual outputs couples every consumer to every producer output name, and one sensitive output moves a whole object out of reach of `tfe_outputs.nonsensitive_values`.

## Decision

Every producer root publishes exactly one non-sensitive `contract` output, and consumers read only `.outputs.contract` (or `.nonsensitive_values.contract`). `scripts/check-contracts.sh` fails CI when a producer lacks the output or marks it sensitive, when a consumer reads any other output, and when two consumers of one upstream declare a `<x>_contract` variable with different types. Two exceptions are allowlisted: the SaaS secret bridge and the `envs/saas` cross-cloud seam. A single-line `try(<ref>.outputs.contract, <ref>.outputs)` fallback is tolerated for the pre-contract outputs and is removed at v1.0 (`UPGRADING.md`).

## Consequences

- Adding a producer output means extending the contract object, and contract types must stay identical across consumers.
- Consumers keep working against an upstream that has not yet applied the contract (the legacy fallback), until v1.0.
- The guard checks shape and names, not that the object's contents are semantically correct.
