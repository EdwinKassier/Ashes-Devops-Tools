# Firebase Modules

This directory groups Firebase-specific Terraform modules. It is a category index, not a deployable Terraform module.

## Modules

| Module | Purpose |
|---|---|
| [`project`](./project/) | Enables Firebase services on an existing GCP project and optionally provisions Apple, Android, and web app resources. |

## Usage Guidance

- Consume these modules from a real root such as [`envs/apps`](../../envs/apps/) or from a dedicated workload composition.
- Review the generated README inside the concrete module directory for provider requirements and inputs.
