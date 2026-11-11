# ADR 0016: Split the AWS organization stage by concern

- Status: Proposed
- Date: 2026-11-11

## Context

`modules/aws/stages/organization` has 63 variables and about 1,460 lines in 10 files. One stage owns:

- the organization, OUs and accounts;
- SCPs, RCPs and declarative policies;
- the TFC OIDC baseline StackSet;
- the AWS Config recorder StackSet;
- the member backup role and vault;
- the guard alerts (EventBridge, SNS, KMS).

Every change to any of these plans the whole stage in the management account, with the most privileged identity. The stage's tests need heavy overrides to stay fast, which hides wiring bugs.

## Decision

Keep one `aws-organization` root and workspace. The management account is one trust boundary, so more workspaces would add more management-account credentials. Split the stage into sub-stages that the root composes:

| Sub-stage | Owns |
|---|---|
| `stages/organization` | Organization, OUs, accounts, delegated administrators |
| `stages/org-policies` | SCPs, RCPs, declarative policies and their attachments |
| `stages/org-baselines` | StackSets: TFC OIDC baseline, Config recorders, member backup role |
| `stages/org-guard-alerts` | Guard-alert rules, topic and key |

Each sub-stage takes typed inputs from the organization sub-stage's outputs. The root keeps `moved` blocks for every address, so state does not change. Each sub-stage ships its own `variables_validation` and `plan_assertions` suites, and tests its wiring against mock providers rather than `override_module`.

## Consequences

- Smaller modules, readable plans and focused tests. The blast radius per apply is unchanged, because it is still one root.
- About 100 `moved` blocks. The sandbox upgrade log must show a no-change plan after the split.
- Do this before the stage grows further. Do not split it into separate workspaces unless the management-account trust model changes.
