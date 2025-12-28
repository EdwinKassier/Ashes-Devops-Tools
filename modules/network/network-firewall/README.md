# Network Firewall Module

This module manages hierarchical firewall rules for a VPC network. It is designed to be used multiple times to create "tiers" of security (e.g., Allow Public -> Compute, Allow Compute -> DB).

## Features

- **Directional**: Supports both `INGRESS` and `EGRESS` rules.
- **Tag-Based**: Targets traffic based on Source/Target Network Tags or Service Accounts.
- **Logging**: Configurable firewall rule logging.
- **Priority**: Explicit priority management.

## Usage

```hcl
module "fw_allow_internal" {
  source = "./modules/network/network-firewall"

  project_id         = "my-project-id"
  firewall_rule_name = "allow-internal-traffic"
  network            = "my-vpc"
  priority           = 65534
  
  allow_rules = [{
    protocol = "tcp"
    ports    = ["0-65535"]
  }]
  
  source_ranges = ["10.0.0.0/8"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `firewall_rule_name`| Name of the rule | `string` | n/a | yes |
| `network` | VPC network name (not URI) | `string` | n/a | yes |
| `allow_rules` | List of allow protocols/ports | `list(object)` | `[]` | no |
| `deny_rules` | List of deny protocols/ports | `list(object)` | `[]` | no |
| `source_ranges` | Source CIDR ranges | `list(string)` | `[]` | no |
| `source_tags` | Source network tags | `list(string)` | `[]` | no |
| `target_tags` | Target network tags | `list(string)` | `[]` | no |
| `priority` | Rule priority (0-65535) | `number` | `1000` | no |

## Outputs

| Name | Description |
|------|-------------|
| `firewall_rule` | The created firewall rule resource |
| `self_link` | The URI of the firewall rule |
