# Google Cloud Landing Zone Environments

This directory (`envs/`) contains the supported Terraform roots for the platform.

## Architecture Guidelines

We utilize a **Hub-and-Spoke** network topology with centralized governance.

### Roots
*   **`organization`**: The control-plane root. Creates the admin project, org policy, shared services projects, folders, and per-environment host projects.
*   **`apps`**: The single application-environment root. Select the environment with `TF_WORKSPACE=apps-<env>` and the matching tfvars file under `envs/apps/examples/`.

### Infrastructure Pattern
Each application environment uses the shared `modules/host` foundation to stamp out:
1.  **VPC Network**: Custom mode with explicit environment CIDR blocks from the organization state.
2.  **Subnets**: 3-Tier architecture (Public, Private, Database).
3.  **Security**: Firewall rules, Cloud Armor, DNS logging, and VPC Service Controls.
4.  **Shared VPC**: Configured as a host project for service-project attachment.

### Workload Provisioning
Do not deploy application services directly into the host project. Instead, use `modules/stages/workload` from a dedicated workload root and attach the resulting service project to the host VPC.

```hcl
module "my_app" {
  source = "../../modules/stages/workload"

  project_name = "my-app-prod"

  folder_id     = data.terraform_remote_state.organization.outputs.environment_config[var.environment].folder_id
  org_id        = data.terraform_remote_state.organization.outputs.org_id
  billing_account = data.terraform_remote_state.organization.outputs.billing_account

  shared_vpc_host_project_id = data.terraform_remote_state.organization.outputs.environment_config[var.environment].host_project_id
  shared_vpc_subnets = {
    private = {
      region      = data.terraform_remote_state.organization.outputs.environment_config[var.environment].region
      subnet_name = "replace-with-private-subnet-name"
    }
  }
}
```
