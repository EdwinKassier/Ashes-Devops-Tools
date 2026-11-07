# ADR 0014: Log-archive PutBucketPolicy stays allowed and is detected

- Status: Accepted
- Date: 2026-11-07

## Context

The log-archive bucket policy is owned by `aws-security`. Blocking `s3:PutBucketPolicy` for its pipeline would break routine updates of that policy.

## Decision

Keep `PutBucketPolicy` and `DeleteBucketPolicy` on the log-archive bucket allowed to the log-archive `tfc-apply` role, exempt in the deny-tamper SCP, and detect changes with the CIS 4.8 alarm in `cloudtrail-org`. Making it break-glass only would require a create-time break-glass apply in every greenfield bootstrap, which costs more than the detection gap. The same trade-off applies to flow-log deletion, detected by Security Hub `EC2.6`. See [known gaps](../known-gaps.md).

## Consequences

- A compromised owning pipeline can rewrite the bucket policy; the change is alerted, not prevented.
- Greenfield bootstrap stays a single normal apply.
- Revisit if break-glass bootstrapping becomes routine.
