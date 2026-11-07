# ADR 0012: CloudTrail delegated administrator

- Status: Proposed
- Date: 2026-11-07

## Context

The organization trail is created by the management account's `aws-security` role, so SCPs, which never restrict the management account, cannot constrain it. That management role can therefore alter org detection.

## Decision

Register security tooling as the CloudTrail delegated administrator with `aws_cloudtrail_organization_delegated_admin_account` (which also creates the service-linked role) and create the trail with the security-tooling provider. The trail still lives in the management account, but a member account manages it, so the existing deny-tamper SCP statements apply, and the management role loses its trail writes. Migration creates the new trail under a different name, verifies delivery, then deletes the old one with break-glass. This is planned (plan Task 1.11) and not yet implemented; the residual is recorded in [known gaps](../known-gaps.md).

## Consequences

- Brings the trail under SCP control. The security-tooling apply role remains exempt from those statements, so SCPs, the boundary and CODEOWNERS cover that residual.
- Needs a migration runbook and an `UPGRADING.md` entry, and must be proven in the sandbox (ADR 0006).
- Until then, trail tampering by the management pipeline is detected, not prevented.
