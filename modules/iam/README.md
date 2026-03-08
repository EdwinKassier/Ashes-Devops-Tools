# IAM Modules

This directory groups the IAM building blocks used across the platform. It is a category index, not a Terraform module.

## Modules

| Module | Purpose |
|---|---|
| [`identity_group`](./identity_group/) | Google Group creation |
| [`identity_group_memberships`](./identity_group_memberships/) | Group membership management |
| [`organization`](./organization/) | Organization and folder IAM bindings |
| [`role`](./role/) | Custom IAM roles |
| [`service_account`](./service_account/) | Service account creation and bindings |
| [`workload_identity`](./workload_identity/) | Workload Identity Federation |

## Usage Guidance

- These modules are typically consumed by [`modules/stages`](../stages/) and the deployable roots in [`envs`](../../envs/).
- Review the generated README in each concrete module directory before direct use.
