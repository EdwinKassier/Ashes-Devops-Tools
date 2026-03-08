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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Cloud NAT Module - Main Configuration

Creates a Cloud NAT gateway with configurable NAT IP allocation,
subnetwork targeting, and logging options.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	network = 
	project_id = 
	region = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_compute_router.router (modules/network/nat/main.tf#L11)
- resource.google_compute_router_nat.nat (modules/network/nat/main.tf#L32)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Name of the Cloud NAT gateway | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The network (self\_link or name) to create the router in | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where the NAT gateway will be created | `string` | n/a | yes |
| <a name="input_create_router"></a> [create\_router](#input\_create\_router) | Whether to create a new Cloud Router. Set to false if using an existing router. | `bool` | `true` | no |
| <a name="input_enable_dynamic_port_allocation"></a> [enable\_dynamic\_port\_allocation](#input\_enable\_dynamic\_port\_allocation) | Enable Dynamic Port Allocation for better port utilization | `bool` | `false` | no |
| <a name="input_enable_endpoint_independent_mapping"></a> [enable\_endpoint\_independent\_mapping](#input\_enable\_endpoint\_independent\_mapping) | Enable endpoint-independent mapping for consistent NAT behavior | `bool` | `null` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable NAT logging | `bool` | `true` | no |
| <a name="input_icmp_idle_timeout_sec"></a> [icmp\_idle\_timeout\_sec](#input\_icmp\_idle\_timeout\_sec) | Timeout for ICMP connections (seconds) | `number` | `30` | no |
| <a name="input_log_filter"></a> [log\_filter](#input\_log\_filter) | NAT log filter: ERRORS\_ONLY, TRANSLATIONS\_ONLY, or ALL | `string` | `"ERRORS_ONLY"` | no |
| <a name="input_max_ports_per_vm"></a> [max\_ports\_per\_vm](#input\_max\_ports\_per\_vm) | Maximum number of ports allocated to a VM (requires enable\_dynamic\_port\_allocation) | `number` | `null` | no |
| <a name="input_min_ports_per_vm"></a> [min\_ports\_per\_vm](#input\_min\_ports\_per\_vm) | Minimum number of ports allocated to a VM | `number` | `64` | no |
| <a name="input_nat_ip_allocate_option"></a> [nat\_ip\_allocate\_option](#input\_nat\_ip\_allocate\_option) | How external IPs should be allocated. AUTO\_ONLY or MANUAL\_ONLY. | `string` | `"AUTO_ONLY"` | no |
| <a name="input_nat_ips"></a> [nat\_ips](#input\_nat\_ips) | List of external IP addresses to use for NAT (when using MANUAL\_ONLY) | `list(string)` | `[]` | no |
| <a name="input_router_asn"></a> [router\_asn](#input\_router\_asn) | BGP ASN for the Cloud Router (optional) | `number` | `null` | no |
| <a name="input_router_name"></a> [router\_name](#input\_router\_name) | Name of the Cloud Router. Required if create\_router is false, otherwise auto-generated. | `string` | `""` | no |
| <a name="input_source_subnetwork_ip_ranges_to_nat"></a> [source\_subnetwork\_ip\_ranges\_to\_nat](#input\_source\_subnetwork\_ip\_ranges\_to\_nat) | How NAT should be applied to subnetworks. ALL\_SUBNETWORKS\_ALL\_IP\_RANGES, ALL\_SUBNETWORKS\_ALL\_PRIMARY\_IP\_RANGES, or LIST\_OF\_SUBNETWORKS. | `string` | `"ALL_SUBNETWORKS_ALL_IP_RANGES"` | no |
| <a name="input_subnetworks"></a> [subnetworks](#input\_subnetworks) | List of subnetworks to NAT (when using LIST\_OF\_SUBNETWORKS) | <pre>list(object({<br/>    name                     = string<br/>    source_ip_ranges_to_nat  = list(string)<br/>    secondary_ip_range_names = optional(list(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_tcp_established_idle_timeout_sec"></a> [tcp\_established\_idle\_timeout\_sec](#input\_tcp\_established\_idle\_timeout\_sec) | Timeout for established TCP connections (seconds) | `number` | `1200` | no |
| <a name="input_tcp_time_wait_timeout_sec"></a> [tcp\_time\_wait\_timeout\_sec](#input\_tcp\_time\_wait\_timeout\_sec) | Timeout for TCP connections in TIME\_WAIT state (seconds) | `number` | `120` | no |
| <a name="input_tcp_transitory_idle_timeout_sec"></a> [tcp\_transitory\_idle\_timeout\_sec](#input\_tcp\_transitory\_idle\_timeout\_sec) | Timeout for transitory TCP connections (seconds) | `number` | `30` | no |
| <a name="input_udp_idle_timeout_sec"></a> [udp\_idle\_timeout\_sec](#input\_udp\_idle\_timeout\_sec) | Timeout for UDP connections (seconds) | `number` | `30` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The ID of the NAT gateway |
| <a name="output_name"></a> [name](#output\_name) | The name of the NAT gateway |
| <a name="output_nat"></a> [nat](#output\_nat) | The NAT gateway resource |
| <a name="output_nat_ips"></a> [nat\_ips](#output\_nat\_ips) | The list of external IP addresses used for NAT |
| <a name="output_region"></a> [region](#output\_region) | The region of the NAT gateway |
| <a name="output_router"></a> [router](#output\_router) | The Cloud Router resource (if created) |
| <a name="output_router_name"></a> [router\_name](#output\_router\_name) | The name of the Cloud Router |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the NAT gateway (same as id for this resource) |
<!-- END_TF_DOCS -->