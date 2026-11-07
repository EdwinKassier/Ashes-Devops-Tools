# ADR 0006: Persistent sandbox estate, which also stages SCPs

- Status: Accepted
- Date: 2026-11-07

## Context

Mock-based `terraform test` asserts planned values and cannot show that an existing estate survives an upgrade, or that a new SCP, boundary or deny leaves the pipeline's own routine actions intact.

## Decision

Maintain a persistent second copy of the landing zone (own HCP organization, GCP organization and AWS organization), described in [sandbox estate](../guides/sandbox-estate.md). It applies every merge to `main` on top of the previous `main`, so each merge is an N-1 to N upgrade. It is also where every new SCP, RCP, boundary or deny policy is applied before release; a policy change is not considered proven by mock tests alone.

## Consequences

- Upgrade and lockout evidence comes from a real cloud, not mocks.
- Cost: a second estate to run, budget-capped by `org.monthly_budget_usd` on the `starter` profile.
- The estate needs its own organizations and a human owner; it is operator-provisioned and cannot be created by CI.
