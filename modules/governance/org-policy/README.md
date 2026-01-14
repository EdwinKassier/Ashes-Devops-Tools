# Organization Policy Module

Applies organization policies (constraints) at org, folder, or project level.

## Features

- Boolean policies (enforce/deny)
- List policies (allowed/denied values)
- Folder and project-level policy overrides

## Usage

```hcl
module "org_policies" {
  source = "../../governance/org-policy"

  org_id = "123456789"

  boolean_policies = [
    {
      constraint = "compute.skipDefaultNetworkCreation"
      enforce    = true
    },
    {
      constraint = "iam.disableServiceAccountKeyCreation"
      enforce    = true
    }
  ]

  list_policies = [
    {
      constraint     = "compute.restrictVpcPeering"
      allowed_values = ["under:organizations/123456789"]
    },
    {
      constraint     = "gcp.resourceLocations"
      allowed_values = ["in:europe-locations"]
    }
  ]
}
```

## Common Policies

| Constraint | Type | Purpose |
|------------|------|---------|
| `compute.skipDefaultNetworkCreation` | Boolean | Prevent default VPC |
| `iam.disableServiceAccountKeyCreation` | Boolean | Enforce keyless auth |
| `compute.requireShieldedVm` | Boolean | Require Shielded VMs |
| `sql.restrictPublicIp` | Boolean | No public IPs on SQL |
| `compute.restrictVpcPeering` | List | Limit VPC peering scope |
| `gcp.resourceLocations` | List | Restrict deployment regions |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| org_id | Organization ID | string | yes |
| boolean_policies | List of boolean constraints | list(object) | no |
| list_policies | List of list constraints | list(object) | no |
