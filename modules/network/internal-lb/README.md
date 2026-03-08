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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Internal HTTP(S) Load Balancer Module - Main Configuration

Creates an internal HTTP(S) load balancer for L7 load balancing
of internal services within a VPC.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	backends = 
	name = 
	network = 
	project_id = 
	region = 
	subnet = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_compute_address.internal_ip (modules/network/internal-lb/main.tf#L14)
- resource.google_compute_firewall.allow_proxy (modules/network/internal-lb/main.tf#L210)
- resource.google_compute_forwarding_rule.forwarding_rule (modules/network/internal-lb/main.tf#L184)
- resource.google_compute_health_check.health_check (modules/network/internal-lb/main.tf#L34)
- resource.google_compute_region_backend_service.backend (modules/network/internal-lb/main.tf#L85)
- resource.google_compute_region_target_http_proxy.http_proxy (modules/network/internal-lb/main.tf#L161)
- resource.google_compute_region_target_https_proxy.https_proxy (modules/network/internal-lb/main.tf#L170)
- resource.google_compute_region_url_map.url_map (modules/network/internal-lb/main.tf#L124)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backends"></a> [backends](#input\_backends) | List of backend instance groups or NEGs | <pre>list(object({<br/>    group           = string<br/>    balancing_mode  = optional(string, "UTILIZATION")<br/>    capacity_scaler = optional(number, 1.0)<br/>    max_utilization = optional(number, 0.8)<br/>    max_connections = optional(number)<br/>    max_rate        = optional(number)<br/>  }))</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Base name for load balancer resources | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The VPC network self\_link or ID | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region for the load balancer | `string` | n/a | yes |
| <a name="input_subnet"></a> [subnet](#input\_subnet) | The subnet self\_link for the load balancer | `string` | n/a | yes |
| <a name="input_allow_global_access"></a> [allow\_global\_access](#input\_allow\_global\_access) | Allow clients from any region to access the load balancer | `bool` | `false` | no |
| <a name="input_backend_port"></a> [backend\_port](#input\_backend\_port) | Backend service port (for firewall rules) | `number` | `80` | no |
| <a name="input_backend_target_tags"></a> [backend\_target\_tags](#input\_backend\_target\_tags) | Network tags for backend instances | `list(string)` | `[]` | no |
| <a name="input_backend_timeout_sec"></a> [backend\_timeout\_sec](#input\_backend\_timeout\_sec) | Backend service timeout in seconds | `number` | `30` | no |
| <a name="input_connection_draining_timeout_sec"></a> [connection\_draining\_timeout\_sec](#input\_connection\_draining\_timeout\_sec) | Connection draining timeout in seconds | `number` | `300` | no |
| <a name="input_create_firewall_rule"></a> [create\_firewall\_rule](#input\_create\_firewall\_rule) | Create firewall rule for proxy-only subnet | `bool` | `true` | no |
| <a name="input_create_health_check"></a> [create\_health\_check](#input\_create\_health\_check) | Whether to create a health check | `bool` | `true` | no |
| <a name="input_create_static_ip"></a> [create\_static\_ip](#input\_create\_static\_ip) | Whether to create a static internal IP address | `bool` | `true` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable access logging | `bool` | `true` | no |
| <a name="input_enable_ssl"></a> [enable\_ssl](#input\_enable\_ssl) | Enable HTTPS for the load balancer | `bool` | `false` | no |
| <a name="input_firewall_priority"></a> [firewall\_priority](#input\_firewall\_priority) | Priority for the proxy-only subnet firewall rule | `number` | `1000` | no |
| <a name="input_grpc_service_name"></a> [grpc\_service\_name](#input\_grpc\_service\_name) | Service name for gRPC health checks | `string` | `null` | no |
| <a name="input_health_check_healthy_threshold"></a> [health\_check\_healthy\_threshold](#input\_health\_check\_healthy\_threshold) | Number of successful checks before marking healthy | `number` | `2` | no |
| <a name="input_health_check_interval_sec"></a> [health\_check\_interval\_sec](#input\_health\_check\_interval\_sec) | Health check interval in seconds | `number` | `5` | no |
| <a name="input_health_check_port"></a> [health\_check\_port](#input\_health\_check\_port) | Port for health checks | `number` | `80` | no |
| <a name="input_health_check_request_path"></a> [health\_check\_request\_path](#input\_health\_check\_request\_path) | Request path for HTTP/HTTPS health checks | `string` | `"/health"` | no |
| <a name="input_health_check_self_link"></a> [health\_check\_self\_link](#input\_health\_check\_self\_link) | Existing health check self\_link (if create\_health\_check is false) | `string` | `null` | no |
| <a name="input_health_check_timeout_sec"></a> [health\_check\_timeout\_sec](#input\_health\_check\_timeout\_sec) | Health check timeout in seconds | `number` | `5` | no |
| <a name="input_health_check_type"></a> [health\_check\_type](#input\_health\_check\_type) | Type of health check: HTTP, HTTPS, TCP, or GRPC | `string` | `"HTTP"` | no |
| <a name="input_health_check_unhealthy_threshold"></a> [health\_check\_unhealthy\_threshold](#input\_health\_check\_unhealthy\_threshold) | Number of failed checks before marking unhealthy | `number` | `2` | no |
| <a name="input_host_rules"></a> [host\_rules](#input\_host\_rules) | Host rules for URL mapping | <pre>list(object({<br/>    hosts        = list(string)<br/>    path_matcher = string<br/>  }))</pre> | `[]` | no |
| <a name="input_ip_address"></a> [ip\_address](#input\_ip\_address) | Static IP address (if create\_static\_ip is false) | `string` | `null` | no |
| <a name="input_is_l7"></a> [is\_l7](#input\_is\_l7) | Whether to create an L7 (HTTP/S) load balancer (true) or L4 TCP (false) | `bool` | `true` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the forwarding rule | `map(string)` | `{}` | no |
| <a name="input_locality_lb_policy"></a> [locality\_lb\_policy](#input\_locality\_lb\_policy) | Locality load balancing policy | `string` | `"ROUND_ROBIN"` | no |
| <a name="input_log_sample_rate"></a> [log\_sample\_rate](#input\_log\_sample\_rate) | Sample rate for access logs (0.0 to 1.0) | `number` | `1` | no |
| <a name="input_path_matchers"></a> [path\_matchers](#input\_path\_matchers) | Path matchers for URL mapping | <pre>list(object({<br/>    name            = string<br/>    default_service = string<br/>    path_rules = optional(list(object({<br/>      paths   = list(string)<br/>      service = string<br/>    })))<br/>  }))</pre> | `[]` | no |
| <a name="input_port_range"></a> [port\_range](#input\_port\_range) | Port range for the forwarding rule (e.g., '80' or '8080-8090') | `string` | `"80"` | no |
| <a name="input_proxy_only_subnet_ranges"></a> [proxy\_only\_subnet\_ranges](#input\_proxy\_only\_subnet\_ranges) | CIDR ranges for proxy-only subnets | `list(string)` | `[]` | no |
| <a name="input_session_affinity"></a> [session\_affinity](#input\_session\_affinity) | Session affinity: NONE, CLIENT\_IP, or GENERATED\_COOKIE | `string` | `"NONE"` | no |
| <a name="input_ssl_certificates"></a> [ssl\_certificates](#input\_ssl\_certificates) | List of SSL certificate self\_links (for HTTPS) | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_service"></a> [backend\_service](#output\_backend\_service) | The backend service resource |
| <a name="output_backend_service_id"></a> [backend\_service\_id](#output\_backend\_service\_id) | The ID of the backend service |
| <a name="output_backend_service_self_link"></a> [backend\_service\_self\_link](#output\_backend\_service\_self\_link) | The self\_link of the backend service |
| <a name="output_forwarding_rule"></a> [forwarding\_rule](#output\_forwarding\_rule) | The full forwarding rule resource |
| <a name="output_health_check"></a> [health\_check](#output\_health\_check) | The health check resource (if created) |
| <a name="output_id"></a> [id](#output\_id) | The ID of the forwarding rule |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | The internal IP address of the load balancer |
| <a name="output_name"></a> [name](#output\_name) | The name of the forwarding rule |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the forwarding rule |
| <a name="output_static_ip_address"></a> [static\_ip\_address](#output\_static\_ip\_address) | The static IP address resource (if created) |
| <a name="output_url_map"></a> [url\_map](#output\_url\_map) | The URL map resource (if L7) |
<!-- END_TF_DOCS -->