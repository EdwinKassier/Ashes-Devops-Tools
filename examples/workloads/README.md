# Workload Examples

These examples are intentionally kept out of `envs/` so the deployable roots stay free of sample resources.

- Use [`service-project.tf`](./service-project.tf) as a starting point for attaching a service project to the Shared VPC created by `envs/apps`.
- Treat the file as a snippet, not a standalone Terraform root. Wire it to your own remote state, variables, and subnet naming before applying it.
