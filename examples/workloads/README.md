# Workload Example

A minimal but production-shaped example of how to attach a service project to the
Shared VPC created by `envs/apps` and apply standardised IAM through the
`modules/stages/workload` module.

## What this creates

| Resource | Notes |
|----------|-------|
| GCP project (via Project Factory) | Billed to your billing account, placed in the specified folder |
| Shared VPC attachment | Service project joined to the host project's VPC |
| Subnet IAM | `roles/compute.networkUser` granted for every listed subnet |
| Project IAM | `project_admin_roles` granted to `project_admin_group_email` (authoritative per role) |

## Prerequisites

- A running `envs/apps` deployment in Terraform Cloud — the workload reads
  `host_project_id`, `folder_id`, and subnet self-links from the org remote state.
- A billing account ID.
- An existing Google Group to act as the project admin group.

## Usage

```bash
# 1. Copy and fill in real values
cp examples/workloads/variables.tf /tmp/my-workload-vars.auto.tfvars  # or use tfvars file

# 2. Initialise
terraform -chdir=examples/workloads init

# 3. Plan
terraform -chdir=examples/workloads plan

# 4. Apply
terraform -chdir=examples/workloads apply
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `project_prefix` | Short prefix for resource naming | `"example"` |
| `environment` | Environment label (`dev`, `staging`, `prod`) | `"dev"` |

All other values (org ID, folder ID, billing account, subnet list) are read from
the hardcoded locals in `main.tf`. Replace these with your own `data.terraform_remote_state`
lookups or variable overrides before applying against real infrastructure.

## ⚠️  Authoritative IAM

`google_project_iam_binding` is **authoritative per role** — on every apply it
replaces all existing members for each listed role. Do not add ad-hoc IAM bindings
directly in the GCP console on any role managed here; they will be removed on the
next Terraform apply.
