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
