# ADR 0012: CloudTrail delegated administrator

- Status: Accepted
- Date: 2026-11-07

## Context

The organization trail is created by the management account's `aws-security` role, so SCPs, which never restrict the management account, cannot constrain it. That management role can therefore alter org detection.

## Decision

Register security tooling as the CloudTrail delegated administrator with `aws_cloudtrail_organization_delegated_admin_account` (which also creates the service-linked roles), from `aws-organization`, and create the trail with the security-tooling provider. The trail still lives in the management account, but a member account manages it, so the existing deny-tamper SCP statements apply, and the management role loses its trail writes. The CloudWatch Logs group, its delivery role and the CIS alarms move to security tooling, because CloudTrail requires them in the calling account.

It is opt-in (`aws.enable_cloudtrail_delegated_admin`, default false), so an existing estate plans no change until it migrates. Migration creates the new trail under a different name next to the old one, verifies delivery, then deletes the old one with break-glass ([runbook](../runbooks/aws-cloudtrail-delegated-admin-migration.md)). Terraform never destroys the old trail: it stays in configuration until the break-glass step, and the management role cannot delete it.

## Consequences

- Brings the trail under SCP control. The security-tooling apply role remains exempt from those statements, so SCPs, the boundary and CODEOWNERS cover that residual.
- Needs the migration runbook and an `UPGRADING.md` entry, and must be proven in the sandbox (ADR 0006) before the scaffolder turns it on. Open items are in [known gaps](../known-gaps.md).
- Until an estate turns it on, trail tampering by the management pipeline is detected, not prevented.
