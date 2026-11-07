# ADR 0013: Security Hub generation and policy language

- Status: Accepted
- Date: 2026-11-07

## Context

Two newer options exist. The unified Security Hub (generally available December 2025; OCSF findings; provider resources `aws_securityhub_*_v2`) replaces Security Hub CSPM (ASFF), which `modules/aws/security/securityhub-org` uses. Terraform Policy (`tfpolicy`) became generally available in Terraform 1.17, while the repo's guardrails are OPA policies under `policies/`.

## Decision

Stay on Security Hub CSPM. Adopt the unified Security Hub when its v2 provider resources leave best-effort status. Keep OPA as the policy language. Evaluate `tfpolicy` for new policies once forks are on Terraform 1.17.

## Consequences

- No migration cost or finding-format change now.
- The repo forgoes OCSF and the new aggregation features until adoption.
- Two policy languages could coexist later; the choice is revisited per new policy, not by rewriting existing ones.
