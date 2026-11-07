# ADR 0008: Keep terraform_remote_state; ephemeral tfe_outputs for the SaaS bridge

- Status: Accepted
- Date: 2026-11-07

## Context

Cross-root reads need a mechanism. `data.terraform_remote_state` is portable across backends, while `tfe_outputs` is HCP-specific. The SaaS secret bridge reads a service-role key and database password, and a data source's result (every output of the producer, not just the ones read) is stored in the reading workload's state.

## Decision

Keep `terraform_remote_state` as the cross-root mechanism for the cloud roots (always reading the single `contract` output, ADR 0003). `envs/tfc-admin` uses `tfe_outputs` for its two bootstrap reads. For the SaaS bridge, the workload roots read the saas outputs only with `ephemeral "tfe_outputs"` (tfe 0.65 or later; the lockfile pins 0.83.0, Terraform 1.17 mocks it in tests). The values flow only into write-only arguments.

The bridged secret's write-only version must be non-ephemeral, but it does **not** come from a non-ephemeral read of the saas workspace. Both `data "terraform_remote_state"` and `data "tfe_outputs"` fetch every output of the workspace and store the whole result in the reader's state, secrets included (`tfe_outputs.values` holds the sensitive outputs). The version therefore comes from `saas.bridge_rotation` in `config/landing-zone.yaml`, the same key the saas root publishes as `bridge_version`, with a per-workload `saas_bridge_version` override. A postcondition on the ephemeral read fails the plan while the published `bridge_version` differs, so a bump can never push the old values under the new version.

## Consequences

- Bridge secrets never reach the consuming workload's plan or state; they stay in the `saas-*` state (provider limitation, [known gaps](../known-gaps.md)).
- After a rotation bump, every bridging workload plan fails until `saas-<name>` applies; each workload is then re-queued (no run trigger). For an emergency change in that window, set `saas_bridge_version` to the old value temporarily.
- The bridge reads with the `saas-outputs-reader` team token (`TFE_TOKEN`), not through remote-state sharing.
- Reads need the producer workspace to share state access with the consumer.
- No broader move to Stacks or `tfe_outputs` for ordinary reads.
