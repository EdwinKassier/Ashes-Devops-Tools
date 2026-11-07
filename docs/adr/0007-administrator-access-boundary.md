# ADR 0007: AdministratorAccess capped by boundary and SCPs

- Status: Accepted
- Date: 2026-11-07

## Context

Terraform applies create arbitrary resource types across accounts. Hand-maintaining a per-layer least-privilege policy for each apply role costs more than it returns for a boilerplate, and drifts with every provider release.

## Decision

The AWS `tfc-apply` role defaults to `AdministratorAccess` (`tfc_apply_role_policy_arns`), capped by the StackSet-embedded `tfc-apply-boundary` permissions boundary and by the organization SCPs. The boundary denies leaving the org, tampering with CloudTrail, GuardDuty, Config and other security services, changing the TFC roles, OIDC provider or the boundary itself, creating `iam:CreateUser` and access keys, and creating roles without the same boundary. The plan role is `ReadOnlyAccess` plus a data-plane read deny. Forks may narrow `apply_role_policy_arns` per account.

## Consequences

- Strong prevention of tamper paths with small maintenance cost.
- Residual risk: the apply role can still alter other pre-existing unbounded roles (control matrix, customer responsibilities).
- Per-layer least-privilege apply policies are deferred as cost greater than value for a boilerplate; revisit if a fork needs a stricter posture.
