# Network Hub Stage Module

Establishes the centralized networking architecture (Hub-and-Spoke topology).

## Purpose

- Creates the **Shared VPC** in a dedicated hub project
- Configures **Cloud DNS** hub for centralized name resolution
- Sets up **VPC Service Controls** perimeters (dry-run initially)
- Implements **Hierarchical Firewall Policies**
- Manages **Interconnect/VPN** gateways (if configured)

## Architecture

This module creates two core projects:
1. `net-hub`: Hosts the Shared VPC code
2. `dns-hub`: Hosts private DNS zones

## Usage

```hcl
module "network_hub" {
  source = "../../modules/stages/network-hub"

  org_id          = "123456789"
  hub_project_id  = "my-org-net-hub"
  dns_project_id  = "my-org-dns-hub"
  
  # DNS Configuration
  internal_domain = "internal.mycompany.com"

  # Spoke Attachments
  spoke_project_ids = {
    "prod-app" = "project-123"
  }
}
```

## Security Features

- **Private Google Access**: Enforced on all subnets
- **VPC-SC**: Data exfiltration protection for sensitive services
- **Firewall**: Default deny ingress, strict egress

## Outputs

- `shared_vpc_self_link`: Self link of the host network
- `dns_hub_zone_name`: Name of the managed zone
