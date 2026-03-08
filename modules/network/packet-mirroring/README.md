# Packet Mirroring Module

Creates packet mirroring policies for network forensics, IDS/IPS integration, and security analysis.

## Features

- Mirror traffic from instances, subnetworks, or by network tags
- Filter by IP protocols, CIDR ranges, and direction
- Send mirrored traffic to internal load balancer collector
- Configurable priority for multiple policies

## Usage

```hcl
module "packet_mirroring" {
  source = "../network/packet-mirroring"

  project_id = "my-project"
  name       = "security-traffic-mirror"
  region     = "us-central1"
  network    = module.vpc.network_self_link

  # Send mirrored traffic to IDS/IPS collector
  collector_ilb_url = module.ids_ilb.forwarding_rule_self_link

  # Mirror all traffic from database subnet
  mirrored_subnetworks = [module.vpc.database_subnets["us-central1-a"].self_link]

  # Or mirror by tags
  mirrored_tags = ["sensitive-workload"]

  # Filter configuration
  filter_ip_protocols = ["tcp", "udp"]
  filter_cidr_ranges  = ["10.0.0.0/8"]
  filter_direction    = "BOTH"

  priority = 1000
  enable   = true
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| project_id | GCP project ID | string | yes |
| name | Name of the policy | string | yes |
| region | Region for the policy | string | yes |
| network | VPC network self_link | string | yes |
| collector_ilb_url | ILB URL for collector | string | yes |
| mirrored_instances | Instances to mirror | list(string) | no |
| mirrored_subnetworks | Subnetworks to mirror | list(string) | no |
| mirrored_tags | Network tags to mirror | list(string) | no |
| filter_ip_protocols | Protocols to mirror | list(string) | no |
| filter_direction | Traffic direction | string | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the policy |
| self_link | The self_link of the policy |
| enabled | Whether the policy is enabled |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Packet Mirroring Module - Main Configuration

Creates packet mirroring policies for network forensics, IDS/IPS,
and security analysis by cloning network traffic to collector instances.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	collector_ilb_url = 
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


- resource.google_compute_packet_mirroring.mirroring (modules/network/packet-mirroring/main.tf#L14)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_collector_ilb_url"></a> [collector\_ilb\_url](#input\_collector\_ilb\_url) | The URL of the internal load balancer to collect mirrored traffic | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the packet mirroring policy | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The VPC network self\_link or ID | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region for the packet mirroring policy | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Description of the packet mirroring policy | `string` | `"Managed by Terraform"` | no |
| <a name="input_enable"></a> [enable](#input\_enable) | Whether the packet mirroring policy is enabled | `bool` | `true` | no |
| <a name="input_filter_cidr_ranges"></a> [filter\_cidr\_ranges](#input\_filter\_cidr\_ranges) | CIDR ranges to filter (traffic matching these ranges will be mirrored) | `list(string)` | `[]` | no |
| <a name="input_filter_direction"></a> [filter\_direction](#input\_filter\_direction) | Direction of traffic to mirror: INGRESS, EGRESS, or BOTH | `string` | `"BOTH"` | no |
| <a name="input_filter_ip_protocols"></a> [filter\_ip\_protocols](#input\_filter\_ip\_protocols) | IP protocols to mirror (e.g., ['tcp', 'udp', 'icmp']) | `list(string)` | `[]` | no |
| <a name="input_mirrored_instances"></a> [mirrored\_instances](#input\_mirrored\_instances) | List of instance self\_links to mirror traffic from | `list(string)` | `[]` | no |
| <a name="input_mirrored_subnetworks"></a> [mirrored\_subnetworks](#input\_mirrored\_subnetworks) | List of subnetwork self\_links to mirror traffic from | `list(string)` | `[]` | no |
| <a name="input_mirrored_tags"></a> [mirrored\_tags](#input\_mirrored\_tags) | List of network tags to identify instances for mirroring | `list(string)` | `[]` | no |
| <a name="input_priority"></a> [priority](#input\_priority) | Priority of the mirroring policy (lower = higher priority) | `number` | `1000` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_collector_ilb"></a> [collector\_ilb](#output\_collector\_ilb) | The collector ILB URL |
| <a name="output_id"></a> [id](#output\_id) | The ID of the packet mirroring policy |
| <a name="output_name"></a> [name](#output\_name) | The name of the packet mirroring policy |
| <a name="output_policy"></a> [policy](#output\_policy) | The full packet mirroring policy resource |
| <a name="output_region"></a> [region](#output\_region) | The region of the packet mirroring policy |
<!-- END_TF_DOCS -->