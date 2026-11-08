# Workload Example

A minimal but production-shaped example of how to attach a service project to an
existing Shared VPC host project and apply standardised IAM through the
`modules/gcp/stages/workload` module.

## What this creates

| Resource | Notes |
|----------|-------|
| GCP project (via `modules/gcp/project`) | Billed to your billing account, placed in the specified folder |
| Shared VPC attachment | Service project joined to the host project's VPC |
| Subnet IAM | `roles/compute.networkUser` granted on every listed subnet (additive) |
| Project IAM | `project_admin_roles` granted to `project_admin_group_email` (additive) |

## Prerequisites

- An existing Shared VPC host project and subnet (in the landing zone, the
  `gcp-projects` and `gcp-network-hub` workspaces own them).
- A folder ID and a billing account ID.
- An existing Google Group to act as the project admin group.

## Values are hard-coded

The org ID, folder ID, billing account, host project and subnet are **hard-coded
placeholders** in the `locals` block at the top of `main.tf`; nothing is read
from remote state. Before you plan against real infrastructure, replace those
locals with your own values, or with `data "terraform_remote_state"` /
`data "tfe_outputs"` lookups of the workspaces that own them.

## Usage

1. Edit the locals in `main.tf` (see above).
2. Optionally override the two input variables in
   `examples/workloads/terraform.tfvars`:

   ```hcl
   project_prefix = "acme"
   environment    = "dev"
   ```

3. Initialise and plan:

   ```bash
   terraform -chdir=examples/workloads init
   terraform -chdir=examples/workloads plan
   ```

This directory is a standalone sandbox. Apply it only in a scratch folder and
billing account; the landing zone itself deploys workloads through the
`gcp-workload-<env>` Terraform Cloud workspaces.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `project_prefix` | Short prefix for resource naming | `"example"` |
| `environment` | Environment label (`dev`, `staging`, `prod`) | `"dev"` |

## Additive IAM

The module grants roles with `google_project_iam_member` and
`google_compute_subnetwork_iam_member`, which are **additive**: Terraform adds
the listed members and leaves every other member of the same role alone. Grants
made outside Terraform survive each apply, so review the project's IAM policy
separately. Removing a role from `project_admin_roles` removes only this
module's grant.
