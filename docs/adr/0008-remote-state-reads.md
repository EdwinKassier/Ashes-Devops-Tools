# ADR 0008: Keep terraform_remote_state; ephemeral tfe_outputs for the SaaS bridge

- Status: Accepted
- Date: 2026-11-07

## Context

Cross-root reads need a mechanism. `data.terraform_remote_state` is portable across backends, while `tfe_outputs` is HCP-specific. The SaaS secret bridge reads a service-role key and database password, and a data source's result is stored in the reading workload's state.

## Decision

Keep `terraform_remote_state` as the cross-root mechanism for the cloud roots (always reading the single `contract` output, ADR 0003). `envs/tfc-admin` uses `tfe_outputs` for its two bootstrap reads. For the SaaS bridge, replace the secret-carrying read with `ephemeral "tfe_outputs"` (tfe 0.65 or later; the lockfile pins 0.83.0), keeping a non-ephemeral `data "tfe_outputs"` only for `bridge_version`. That change is open work tracked in [known gaps](../known-gaps.md) and waits on the test toolchain.

## Consequences

- Until the ephemeral read ships, bridge secrets can reach the consuming workload's state.
- Reads need the producer workspace to share state access with the consumer.
- No broader move to Stacks or `tfe_outputs` for ordinary reads.
