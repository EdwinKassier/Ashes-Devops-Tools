# ADR 0005: HCP Terraform as the default backend; Stacks deferred

- Status: Accepted
- Date: 2026-11-07

## Context

State, runs, dynamic credentials, policy sets and run triggers all depend on the backend. The roots must pick one default, and HCP Terraform Stacks are the newer alternative to workspaces.

## Decision

Every root uses an HCP Terraform `cloud {}` backend and workspaces managed by `envs/tfc-admin`. Operators who cannot use HCP Terraform can copy `templates/backend/gcs_override.tf.example` or `s3_override.tf.example` into a root as `backend_override.tf`, which replaces the `cloud {}` block. Stacks were evaluated and deferred. Stacks are generally available, but adopting them would rewrite every root, and custom deployment groups need the Premium tier.

## Consequences

- Dynamic credentials, run triggers and OPA policy sets work as designed; forks need an HCP Terraform organization.
- Revisit Stacks when the rewrite cost is justified or the tier restriction no longer applies.
- Non-HCP backends lose run triggers, policy sets and the tfc-admin workspace layer.
