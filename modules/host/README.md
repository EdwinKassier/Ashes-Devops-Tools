# Host Module

Unified infrastructure orchestration module that serves as the central entrypoint for project provisioning.

## Overview

This module instantiates and coordinates all network, security, and governance modules to provide a complete infrastructure foundation. It eliminates the need to manually wire together individual modules and ensures consistent configuration across all components.

## Features

- **Core Networking**: VPC with tiered subnets (public/private/database), NAT gateway, and flow logging
- **Edge Security**: Cloud Armor WAF with OWASP Top 10 protection and adaptive DDoS defense
- **Content Delivery**: Global Load Balancer with Cloud CDN and HTTP→HTTPS redirect
- **DNS Management**: Public and private DNS zones with DNSSEC support
- **Hybrid Connectivity**: HA VPN with BGP routing
- **Network Peering**: VPC peering for hub-and-spoke architectures
- **API Management**: API Gateway with OpenAPI spec support

## Usage

### Minimal Example

```hcl
module "infrastructure" {
  source = "../modules/host"

  project_id     = "my-project-id"
  project_prefix = "myapp-dev"
  region         = "us-central1"

  enable_networking = true
}
```

### Production Example

```hcl
module "infrastructure" {
  source = "../modules/host"

  project_id     = "my-project-id"
  project_prefix = "myapp-prod"
  region         = "us-central1"

  # Networking
  enable_networking              = true
  vpc_name                       = "production-vpc"
  enable_private_service_access  = true
  enable_private_service_connect = true
  enable_deletion_protection     = true

  # Security
  enable_cloud_armor         = true
  enable_owasp_rules         = true
  enable_adaptive_protection = true
  owasp_sensitivity          = 2

  # CDN
  enable_cdn   = true
  cdn_domains  = ["app.example.com", "api.example.com"]
  
  # DNS
  dns_zones = {
    "example-public" = {
      dns_name   = "example.com."
      visibility = "public"
      dnssec_enabled = true
    }
    "example-private" = {
      dns_name   = "internal.example.com."
      visibility = "private"
    }
  }

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
```

## Inputs

See [variables.tf](variables.tf) for the complete list of input variables.

### Key Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `project_id` | The GCP project ID | `string` | **required** |
| `project_prefix` | Prefix for resource naming | `string` | **required** |
| `region` | Primary GCP region | `string` | `"us-central1"` |
| `enable_networking` | Enable VPC provisioning | `bool` | `true` |
| `enable_cloud_armor` | Enable Cloud Armor WAF | `bool` | `true` |
| `enable_cdn` | Enable CDN/Global LB | `bool` | `false` |
| `enable_vpn` | Enable Cloud VPN | `bool` | `false` |

## Outputs

See [outputs.tf](outputs.tf) for the complete list of outputs.

### Key Outputs

| Name | Description |
|------|-------------|
| `network_id` | The VPC network ID |
| `network_self_link` | The VPC network self link |
| `subnets` | All subnet outputs by tier |
| `security_policy_self_link` | Cloud Armor policy self link |
| `cdn_ip` | Global load balancer IP |
| `dns_name_servers` | Name servers for public zones |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host Module                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌───────────────┐  ┌─────────────────────┐   │
│  │     VPC     │  │  Cloud Armor  │  │        CDN          │   │
│  │  + Subnets  │  │  + OWASP WAF  │  │ + Global LB         │   │
│  │  + NAT      │  │  + Adaptive   │  │ + SSL Cert          │   │
│  │  + Firewall │  │               │  │ + HTTP Redirect     │   │
│  └─────────────┘  └───────────────┘  └─────────────────────┘   │
│                                                                  │
│  ┌─────────────┐  ┌───────────────┐  ┌─────────────────────┐   │
│  │     DNS     │  │      VPN      │  │    API Gateway      │   │
│  │  + Public   │  │  + HA VPN     │  │  + OpenAPI          │   │
│  │  + Private  │  │  + BGP        │  │  + Serverless NEG   │   │
│  │  + DNSSEC   │  │  + Tunnels    │  │                     │   │
│  └─────────────┘  └───────────────┘  └─────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     VPC Peering                           │   │
│  │               (Hub-and-Spoke Connectivity)                │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| google | >= 4.80.0 |
| google-beta | >= 4.80.0 |

## License

Copyright 2023 Ashes
