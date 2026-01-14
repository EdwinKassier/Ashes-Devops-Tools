# Google Cloud Landing Zone Environments

This directory (`envs/`) contains the Terraform configurations for the organization's core Google Cloud environments.

## Architecture Guidelines

We utilize a **Hub-and-Spoke** network topology with centralized governance.

### Environments
*   **`organisation`**: The root of trust. Contains Org Policies, Folder structure, Billing, and centralized SCC/Logging. configuration.
*   **`dev`**: Development environment. Optimized for developer velocity. Lower security thresholds (e.g., lower budget alerts, no VPC-SC).
*   **`uat`**: User Acceptance Testing. **Must mirror Production** in terms of network security (VPC-SC, Firewalls) to validate application behavior before promotion.
*   **`prod`**: Production. High Availability (HA), Strict Security (VPC-SC, Cloud Armor, deletion protection), and long-term log retention.

### Infrastructure Pattern
Each environment uses the shared `modules/host` (Environment Foundation) to stamp out:
1.  **VPC Network**: Custom mode with consistent naming.
2.  **Subnets**: 3-Tier architecture (Public, Private, Database).
3.  **Security**: Firewall rules ("Allow Internal", "Deny All Ingress"), Cloud Armor (Prod), VPC Service Controls (Prod/UAT).
4.  **Shared VPC**: Configured as a Host Project to allow service project attachment.

### Workload Provisioning
Do not deploy applications directly into the Host Project. Instead, use the `modules/stages/workload` module to create a **Service Project** and attach it to the Host VPC.

```hcl
module "my_app" {
  source = "../../modules/stages/workload"
  
  project_name               = "my-app-prod"
  shared_vpc_host_project_id = module.host.project_id
  # ...
}
```
