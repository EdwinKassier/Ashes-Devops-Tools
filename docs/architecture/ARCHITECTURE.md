# System Architecture

## Overview

This repository implements a GCP landing zone with two supported Terraform roots:

- `envs/organization` for the control plane
- `envs/apps` for environment-specific application infrastructure

The design target is a low-touch platform that is easy to extend without copying roots or editing workflow matrices.

## Supported Roots

```text
envs/
├── organization/
└── apps/
```

### `envs/organization`

Creates and manages:

- admin project
- Terraform admin service account
- workload identity providers
- folders and folder IAM
- shared projects
- per-environment host projects
- org policy
- tags
- centralized audit logging
- SCC notifications
- billing export and budgets
- hub networking

This root composes four stage modules:

- `modules/stages/bootstrap`
- `modules/stages/organization`
- `modules/stages/projects`
- `modules/stages/network-hub`

### `envs/apps`

Consumes remote state from the `organization` workspace and deploys one environment at a time into the selected host project.

The workspace naming contract is:

- `organization`
- `apps-dev`
- `apps-uat`
- `apps-prod`
- `apps-<env>` for any new environment

## Environment Model

The canonical environment contract lives in `envs/organization/variables.tf`:

```hcl
map(object({
  display_name            = string
  region                  = string
  cidr_block              = string
  budget_monthly_limit    = number
  iam_group_role_bindings = map(set(string))
  labels                  = optional(map(string), {})
}))
```

That keeps CIDRs explicit and stable. The old pattern of deriving CIDRs from key ordering is no longer part of the platform.

## Module Layering

### Stage Modules

- `modules/stages/bootstrap`
  - admin project
  - Terraform admin service account
  - GitHub and Terraform Cloud workload identity

- `modules/stages/organization`
  - folders
  - tags
  - org policy
  - audit logging
  - SCC notifications
  - billing export

- `modules/stages/projects`
  - shared platform projects
  - one host project per declared environment

- `modules/stages/network-hub`
  - shared hub VPC
  - shared DNS
  - hierarchical firewall
  - organization-spanning connectivity

- `modules/stages/workload`
  - separate service projects that attach to a Shared VPC host

### Shared Infrastructure Modules

- `modules/network/*` contains the reusable network primitives
- `modules/governance/*` contains budgets, logging, KMS, org policy, SCC, and tags
- `modules/iam/*` contains reusable IAM primitives
- `modules/host` remains the compatibility wrapper used by `envs/apps`

## State and Execution Model

### Control Flow

```mermaid
graph TD
    A["envs/organization"] -->|workspace: organization| B["Terraform Cloud state"]
    B --> C["envs/apps"]
    C -->|workspace: apps-<env>| D["Host project infrastructure"]
    E["Dedicated workload root"] --> F["modules/stages/workload"]
    F --> D
```

### Responsibilities

- Terraform Cloud owns remote state and live plan/apply execution.
- GitHub Actions validates code on pull requests.
- Release tags only publish GitHub release metadata after confirming a successful Terraform Cloud run.

GitHub tags do **not** apply infrastructure directly.

## CI/CD

### Pull Requests

The validation workflow runs:

- `terraform fmt -check`
- terraform-docs drift check
- `terraform init -backend=false`
- `terraform validate`
- `tflint`
- `tfsec`
- `checkov`

### Tags

The release-metadata workflow listens for:

- `organization/vX.Y.Z`
- `apps/<env>/vX.Y.Z`

It verifies the latest Terraform Cloud run for the matching workspace and then publishes a GitHub release.

## Operator Model

### Control Plane

```bash
terraform -chdir=envs/organization init
terraform -chdir=envs/organization plan
```

### App Environment

```bash
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
```

### Workload Projects

Service projects should be created from a dedicated workload root that calls `modules/stages/workload`. They should not be created inside the host project itself.

## Current Boundaries

- The repository does not yet include a first-class workload root beyond the examples.
- Local `make validate-all` requires access to `registry.terraform.io`.
- Local `make lint` depends on a healthy TFLint Google ruleset plugin installation.
