# Cloud CDN Module (Global Load Balancer)

This module provisions a Global External HTTPS Load Balancer served via Cloud CDN. It is the primary entrypoint for public internet traffic.

## Features

- **Global Reach**: Uses Google's global edge network.
- **SSL Termination**: Manages Google-managed SSL certificates automatically.
- **Dynamic Backends**: Supports multiple backend types (Serverless NEGs, Instance Groups) via a flexible configuration list.
- **Security**: Integrated Cloud Armor security policies.
- **CDN**: Caching enabled by default (configurable per backend).

## Usage

```hcl
module "cdn" {
  source = "./modules/network/cdn"

  project_id = "my-project-id"
  lb_name    = "main-lb"
  domains    = ["example.com", "www.example.com"]

  backend_groups = [
    {
      group = module.api_gateway.serverless_neg_id
      description = "API Gateway Backend"
    }
  ]

  security_policy = module.cloud_armor.policy_self_link
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `lb_name` | Name of the Load Balancer | `string` | n/a | yes |
| `domains` | List of domains for SSL certs | `list(string)` | n/a | yes |
| `backend_groups` | List of backend objects | `list(object)` | `[]` | yes |
| `security_policy` | Cloud Armor policy self-link | `string` | `null` | no |
| `enable_cdn` | Enable CDN features | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `load_balancer_ip` | The reserved global static IP |
| `backend_service_id` | The backend service ID |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

CDN Module - Main Configuration

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	lb_name = 
	project_id = 
	
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


- resource.google_compute_backend_service.default (modules/network/cdn/main.tf#L31)
- resource.google_compute_global_address.default (modules/network/cdn/main.tf#L12)
- resource.google_compute_global_forwarding_rule.default (modules/network/cdn/main.tf#L82)
- resource.google_compute_global_forwarding_rule.http_redirect (modules/network/cdn/main.tf#L120)
- resource.google_compute_managed_ssl_certificate.default (modules/network/cdn/main.tf#L19)
- resource.google_compute_target_http_proxy.redirect (modules/network/cdn/main.tf#L111)
- resource.google_compute_target_https_proxy.default (modules/network/cdn/main.tf#L73)
- resource.google_compute_url_map.default (modules/network/cdn/main.tf#L65)
- resource.google_compute_url_map.redirect (modules/network/cdn/main.tf#L97)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_lb_name"></a> [lb\_name](#input\_lb\_name) | Name for the load balancer resources | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the CDN resources will be created | `string` | n/a | yes |
| <a name="input_backend_groups"></a> [backend\_groups](#input\_backend\_groups) | List of Backend references (Instance Groups or NEGs) with configuration | <pre>list(object({<br/>    group           = string<br/>    balancing_mode  = optional(string)<br/>    capacity_scaler = optional(number)<br/>    description     = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_cdn_policy"></a> [cdn\_policy](#input\_cdn\_policy) | Cloud CDN configuration policy | <pre>object({<br/>    cache_mode                   = optional(string, "CACHE_ALL_STATIC")<br/>    client_ttl                   = optional(number, 3600)<br/>    default_ttl                  = optional(number, 3600)<br/>    max_ttl                      = optional(number, 86400)<br/>    negative_caching             = optional(bool, true)<br/>    signed_url_cache_max_age_sec = optional(number, 0)<br/>  })</pre> | `{}` | no |
| <a name="input_domains"></a> [domains](#input\_domains) | List of domains for the managed SSL certificate. If empty, no SSL cert is created. | `list(string)` | `[]` | no |
| <a name="input_enable_cdn"></a> [enable\_cdn](#input\_enable\_cdn) | Enable Cloud CDN for this Global Load Balancer | `bool` | `true` | no |
| <a name="input_enable_http_redirect"></a> [enable\_http\_redirect](#input\_enable\_http\_redirect) | Enable HTTP to HTTPS redirect (recommended for production) | `bool` | `true` | no |
| <a name="input_security_policy"></a> [security\_policy](#input\_security\_policy) | Self link of a Cloud Armor security policy to attach to the backend service | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_service_id"></a> [backend\_service\_id](#output\_backend\_service\_id) | The ID of the backend service |
| <a name="output_backend_service_self_link"></a> [backend\_service\_self\_link](#output\_backend\_service\_self\_link) | The self link of the backend service |
| <a name="output_https_proxy_id"></a> [https\_proxy\_id](#output\_https\_proxy\_id) | The ID of the HTTPS proxy |
| <a name="output_id"></a> [id](#output\_id) | The ID of the CDN load balancer IP address |
| <a name="output_load_balancer_ip"></a> [load\_balancer\_ip](#output\_load\_balancer\_ip) | The global IP address of the load balancer |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self link of the backend service |
| <a name="output_url_map_id"></a> [url\_map\_id](#output\_url\_map\_id) | The ID of the URL map |
<!-- END_TF_DOCS -->