# Governance Modules

This directory groups the governance and platform-control modules used by [`envs/organization`](../../envs/organization/). It is a category index, not a Terraform module.

## Modules

| Module | Purpose |
|---|---|
| [`billing`](./billing/) | Budgets and billing alerts |
| [`cloud-audit-logs`](./cloud-audit-logs/) | Centralized audit log storage and export |
| [`kms`](./kms/) | Customer-managed encryption keys |
| [`org-policy`](./org-policy/) | Organization policy constraints |
| [`scc`](./scc/) | Security Command Center configuration |
| [`tags`](./tags/) | Resource Manager tags and values |

## Usage Guidance

- Prefer the stage modules and deployable roots over calling these modules directly unless you are composing a custom platform root.
- Use each module's generated README for exact provider, input, and output contracts.
