# Cloud NAT Module

This module creates a Cloud NAT gateway with configurable options for NAT IP allocation, subnetwork targeting, port allocation, and logging.

## Features

- **Flexible Router Configuration**: Create a new Cloud Router or use an existing one
- **NAT IP Allocation**: Auto or manual IP allocation
- **Subnetwork Targeting**: NAT all subnets or specific ones
- **Dynamic Port Allocation**: Enable for better port utilization
- **Logging**: Configurable NAT logging

## Usage

### Basic Usage (Auto NAT IPs, All Subnets)

```hcl
module "nat" {
  source = "../nat"

  project_id = "my-project"
  name       = "my-nat"
  region     = "us-central1"
  network    = module.vpc.network_self_link
}
```

### With Existing Router

```hcl
module "nat" {
  source = "../nat"

  project_id    = "my-project"
  name          = "my-nat"
  region        = "us-central1"
  network       = module.vpc.network_self_link
  create_router = false
  router_name   = "existing-router"
}
```

### Specific Subnets Only

```hcl
module "nat" {
  source = "../nat"

  project_id                         = "my-project"
  name                               = "my-nat"
  region                             = "us-central1"
  network                            = module.vpc.network_self_link
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = [
    {
      name                    = module.vpc.private_subnets["us-central1-a"].self_link
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    },
    {
      name                    = module.vpc.database_subnets["us-central1-a"].self_link
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  ]
}
```

### With Dynamic Port Allocation

```hcl
module "nat" {
  source = "../nat"

  project_id                     = "my-project"
  name                           = "my-nat"
  region                         = "us-central1"
  network                        = module.vpc.network_self_link
  enable_dynamic_port_allocation = true
  min_ports_per_vm               = 32
  max_ports_per_vm               = 65536
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The GCP project ID | `string` | n/a | yes |
| name | Name of the Cloud NAT gateway | `string` | n/a | yes |
| region | The region where the NAT gateway will be created | `string` | n/a | yes |
| network | The network to create the router in | `string` | n/a | yes |
| create_router | Whether to create a new Cloud Router | `bool` | `true` | no |
| router_name | Name of the Cloud Router | `string` | `""` | no |
| nat_ip_allocate_option | How external IPs should be allocated | `string` | `"AUTO_ONLY"` | no |
| source_subnetwork_ip_ranges_to_nat | How NAT should be applied to subnetworks | `string` | `"ALL_SUBNETWORKS_ALL_IP_RANGES"` | no |
| enable_logging | Enable NAT logging | `bool` | `true` | no |
| log_filter | NAT log filter | `string` | `"ERRORS_ONLY"` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the NAT gateway |
| self_link | The self_link of the NAT gateway |
| name | The name of the NAT gateway |
| nat_ips | The list of external IP addresses used for NAT |
| router_name | The name of the Cloud Router |
