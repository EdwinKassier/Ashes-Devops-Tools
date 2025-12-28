# Internal HTTP(S) Load Balancer Module

Creates an internal HTTP(S) load balancer for L7 load balancing of internal services.

## Features

- L7 HTTP/HTTPS load balancing
- URL-based routing with host and path matching
- Health checks (HTTP, HTTPS, TCP, gRPC)
- Session affinity and locality policies
- SSL/TLS termination
- Global access option
- Access logging

## Usage

### Basic L7 Load Balancer

```hcl
module "internal_lb" {
  source = "../network/internal-lb"

  project_id = "my-project"
  name       = "api-internal-lb"
  region     = "us-central1"
  network    = module.vpc.network_self_link
  subnet     = module.vpc.private_subnets["us-central1-a"].self_link

  is_l7      = true
  port_range = "80"

  backends = [
    {
      group           = google_compute_instance_group.api_servers.self_link
      balancing_mode  = "UTILIZATION"
      max_utilization = 0.8
    }
  ]

  health_check_type         = "HTTP"
  health_check_port         = 8080
  health_check_request_path = "/health"

  # Allow cross-region access
  allow_global_access = true

  # Firewall for proxy-only subnet
  create_firewall_rule     = true
  proxy_only_subnet_ranges = ["10.129.0.0/23"]
  backend_target_tags      = ["api-server"]
}
```

### L7 with URL Routing

```hcl
module "internal_lb_routed" {
  source = "../network/internal-lb"

  project_id = "my-project"
  name       = "services-lb"
  region     = "us-central1"
  network    = module.vpc.network_self_link
  subnet     = module.vpc.private_subnets["us-central1-a"].self_link

  is_l7      = true
  port_range = "443"
  enable_ssl = true
  ssl_certificates = [google_compute_region_ssl_certificate.cert.self_link]

  backends = [
    { group = google_compute_instance_group.default.self_link }
  ]

  host_rules = [
    { hosts = ["api.internal"], path_matcher = "api-paths" }
  ]

  path_matchers = [
    {
      name            = "api-paths"
      default_service = google_compute_region_backend_service.default.self_link
      path_rules = [
        { paths = ["/v1/*"], service = google_compute_region_backend_service.v1.self_link },
        { paths = ["/v2/*"], service = google_compute_region_backend_service.v2.self_link }
      ]
    }
  ]
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| project_id | GCP project ID | string | yes |
| name | Base name for resources | string | yes |
| region | Region for the LB | string | yes |
| network | VPC network self_link | string | yes |
| subnet | Subnet self_link | string | yes |
| backends | Backend instance groups/NEGs | list(object) | yes |
| is_l7 | L7 (true) or L4 (false) | bool | no |
| port_range | Port range | string | no |
| enable_ssl | Enable HTTPS | bool | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the forwarding rule |
| self_link | The self_link of the forwarding rule |
| ip_address | The internal IP address |
| backend_service | The backend service resource |
