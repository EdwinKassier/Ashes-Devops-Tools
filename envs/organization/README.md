# Organization Root

`envs/organization` is the control-plane root for the platform. It creates the admin project, organization/folder policy, shared hub projects, per-environment host projects, and the downstream contract consumed by `envs/apps`.

## What It Creates

- One admin project for Terraform automation and workload identity
- One shared services folder containing the hub and DNS projects
- One folder and host project per entry in `var.environments`
- Centralized org policy, audit logging, tags, and platform budgets

## Source Of Truth

Application environments are declared once through `var.environments`. Each entry must provide:

- `display_name`
- `region`
- `cidr_block`
- `budget_monthly_limit`
- `iam_group_role_bindings`
- `labels`

See [`terraform.tfvars.example`](./terraform.tfvars.example) for the expected shape.
