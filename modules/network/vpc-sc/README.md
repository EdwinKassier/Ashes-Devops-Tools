# VPC Service Controls Module

Creates VPC Service Controls perimeters to protect GCP resources from data exfiltration and unauthorized access.

## Features

- Create and manage access policies (org-level)
- Define access levels with IP, identity, device, and geo conditions
- Create regular and bridge service perimeters
- Configure ingress and egress policies
- Restrict GCP API access to perimeter boundaries

## Usage

```hcl
module "vpc_sc" {
  source = "../network/vpc-sc"

  organization_id    = "organizations/123456789"
  access_policy_name = "123456789"  # Existing policy number

  perimeter_name  = "production_perimeter"
  perimeter_title = "Production Data Perimeter"

  protected_projects = [
    "111111111111",  # Project numbers (not IDs)
    "222222222222",
  ]

  restricted_services = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
  ]

  access_levels = [
    {
      name  = "corporate_network"
      title = "Corporate Network Access"
      conditions = [{
        ip_subnetworks = ["10.0.0.0/8", "172.16.0.0/12"]
      }]
    },
    {
      name  = "trusted_identities"
      title = "Trusted Service Accounts"
      conditions = [{
        members = ["serviceAccount:ci-cd@project.iam.gserviceaccount.com"]
      }]
    }
  ]

  ingress_policies = [
    {
      identity_type = "ANY_IDENTITY"
      sources       = [{ access_level = "corporate_network" }]
      operations    = [{ service_name = "storage.googleapis.com" }]
    }
  ]
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| organization_id | Organization ID | string | yes |
| perimeter_name | Name of the perimeter | string | yes |
| perimeter_title | Human-readable title | string | yes |
| protected_projects | Project numbers to protect | list(string) | no |
| restricted_services | GCP services to restrict | list(string) | no |
| access_levels | Access level definitions | list(object) | no |
| ingress_policies | Ingress policy rules | list(object) | no |
| egress_policies | Egress policy rules | list(object) | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the service perimeter |
| self_link | The resource name of the perimeter |
| access_levels | Map of created access levels |
| perimeter | The full perimeter resource |
