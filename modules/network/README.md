# Network Modules Library

This directory contains a suite of Terraform modules for building enterprise-grade network infrastructure on Google Cloud Platform (GCP).

## Modules Overview

### Core Networking
| Module | Description | Key Features |
|os|---|---|
| [`vpc`](./vpc) | Creates a VPC network | Global/Regional routing, Shared VPC Host support |
| [`subnet`](./subnet) | Creates subnets | Flow logs, Private Google Access, Secondary Ranges |
| [`nat`](./nat) | Cloud NAT Gateway | Manual/Auto IP allocation, Logging |
| [`shared-vpc-service`](./shared-vpc-service) | Shared VPC Service | Service Project attachment to Host Project |

### Security & Governance
| Module | Description | Key Features |
|---|---|---|
| [`network-firewall`](./network-firewall) | VPC Firewall Rules | Ingress/Egress, Logging, Tag-based matching |
| [`hierarchical-firewall`](./hierarchical-firewall) | Policy-based Firewall | Org/Folder level policies, Batch rules |
| [`vpc-sc`](./vpc-sc) | VPC Service Controls | Service Perimeters, Access Levels |
| [`cloud_armor`](./cloud_armor) | Web Application Firewall | OWASP rules, Adaptive Protection |

### Connectivity
| Module | Description | Key Features |
|---|---|---|
| [`vpn`](./vpn) | Cloud HA VPN | High Availability, BGP dynamic routing |
| [`interconnect`](./interconnect) | Cloud Interconnect | Dedicated/Partner interconnects, SLA support |
| [`vpc-peering`](./vpc-peering) | VPC Network Peering | Bi-directional peering, Route export/import |
| [`private-service-connect`](./private-service-connect) | Private Service Connect | Consumer endpoints for Google APIs |
| [`private-service-access`](./private-service-access) | Private Service Access | VPC Peering for Google Managed Services (SQL/Redis) |

### Application Delivery
| Module | Description | Key Features |
|---|---|---|
| [`cdn`](./cdn) | Cloud CDN & Load Balancer | Global External LB, SSL management, Backend buckets |
| [`dns`](./dns) | Cloud DNS | Public/Private zones, DNSSEC, Forwarding |
| [`api_gateway`](./api_gateway) | API Gateway | OpenAPI spec management, Service Account integration |
| [`internal-lb`](./internal-lb) | Internal Load Balancer | L4/L7 Internal Load Balancing |

### Monitoring & Utilities
| Module | Description | Key Features |
|---|---|---|
| [`vpc-flow-logs`](./vpc-flow-logs) | Flow Logs Export | Sink to BigQuery/GCS for analysis |
| [`packet-mirroring`](./packet-mirroring) | Traffic Inspection | Mirrors traffic to collector ILB |

## Usage Guidelines

### 1. Orchestration
The `modules/host` module is the recommended entry point for new environments. It orchestrates a 3-tier architecture (Public, Compute, Database) secure-by-default network:
- **Public**: Exposed to internet via LB/Gateway.
- **Compute**: Application logic, private IPs only, access to Internet via NAT.
- **Database**: Strictly internal, no direct egress.

### 2. Standardization
All modules export the following standard outputs where applicable:
- `id`: The resource ID.
- `self_link`: The fully qualified resource URI.
- `name`: The resource name.

### 3. Shared VPC
For enterprise setups, use the `vpc` module with `enable_shared_vpc_host = true`, and attach projects using `shared-vpc-service`.

## Best Practices
- **Firewalls**: Use `target_tags` for granular control instead of IP ranges where possible.
- **Naming**: Module resources typically use the `name` variable as a prefix or full name.
- **State**: Ensure remote state usage for production networking to prevent conflicts.

---
*Copyright 2023 Ashes*

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
}
```

## Requirements

No requirements.

## Providers

No providers.



## Resources

The following resources are created:




## Inputs

No inputs.

## Outputs

No outputs.

## Security Considerations

- Ensure all sensitive variables are marked as `sensitive = true`
- Use GCP Secret Manager for storing secrets
- Follow the principle of least privilege for IAM roles
- Enable audit logging for compliance

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

This module is licensed under the MIT License. See [LICENSE](../../LICENSE) for details.
<!-- END_TF_DOCS -->