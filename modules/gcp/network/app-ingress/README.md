# app-ingress

Golden-path front door for a Cloud Run service (audit C1). Composes a global
external HTTPS load balancer in front of a Cloud Run service: a reserved anycast
IP, a Google-managed certificate, an HTTP-to-HTTPS redirect, and optional Cloud
Armor and Cloud DNS records.

## What it creates

- A reserved global IP (anycast).
- A serverless network endpoint group (NEG) targeting the Cloud Run service.
- A backend service (HTTPS, access logging on, optional Cloud Armor, optional CDN).
- A URL map, HTTPS target proxy, and 443 forwarding rule.
- A Google-managed SSL certificate covering `var.domains`.
- An HTTP (80) listener that redirects to HTTPS (no plaintext serving).
- Optionally, one Cloud DNS A record per domain (when `dns_managed_zone` is set).

## Secure by default

- No plaintext: the only content path is HTTPS; HTTP is redirect-only.
- Access logging is always on for the backend service.
- Cloud Armor is opt-in via `security_policy_id`; attach an edge WAF or rate-limit
  policy for internet-facing services.
- TLS floor is opt-in via `ssl_policy_id`; set a MODERN or RESTRICTED SSL policy to
  pin a minimum TLS version.

## Usage

```hcl
module "service" {
  source     = "../../../modules/gcp/compute/cloud-run"
  project_id = local.env_config.host_project_id
  location   = local.env_config.region
  name       = "my-api"
  # ...
}

module "ingress" {
  source                 = "../../../modules/gcp/network/app-ingress"
  project_id             = local.env_config.host_project_id
  region                 = local.env_config.region
  name                   = "my-api"
  domains                = ["api.example.com"]
  cloud_run_service_name = module.service.name
  dns_managed_zone       = "app-zone"       # optional, creates the A record
  security_policy_id     = module.edge.policy_id  # optional Cloud Armor
}
```

The managed certificate provisions only after the domain resolves to the load
balancer IP. If you do not set `dns_managed_zone`, point an A record at the
`ip_address` output yourself.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	cloud_run_service_name =
	domains =
	name =
	project_id =
	region =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |



## Resources

The following resources are created:


- resource.google_compute_backend_service.this (modules/gcp/network/app-ingress/main.tf#L25)
- resource.google_compute_global_address.this (modules/gcp/network/app-ingress/main.tf#L7)
- resource.google_compute_global_forwarding_rule.http (modules/gcp/network/app-ingress/main.tf#L97)
- resource.google_compute_global_forwarding_rule.https (modules/gcp/network/app-ingress/main.tf#L69)
- resource.google_compute_managed_ssl_certificate.this (modules/gcp/network/app-ingress/main.tf#L50)
- resource.google_compute_region_network_endpoint_group.this (modules/gcp/network/app-ingress/main.tf#L14)
- resource.google_compute_target_http_proxy.redirect (modules/gcp/network/app-ingress/main.tf#L91)
- resource.google_compute_target_https_proxy.this (modules/gcp/network/app-ingress/main.tf#L59)
- resource.google_compute_url_map.redirect (modules/gcp/network/app-ingress/main.tf#L80)
- resource.google_compute_url_map.this (modules/gcp/network/app-ingress/main.tf#L44)
- resource.google_dns_record_set.this (modules/gcp/network/app-ingress/main.tf#L108)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_run_service_name"></a> [cloud\_run\_service\_name](#input\_cloud\_run\_service\_name) | Name of the Cloud Run service in var.region the serverless NEG routes to (e.g. the name output of modules/gcp/compute/cloud-run). | `string` | n/a | yes |
| <a name="input_domains"></a> [domains](#input\_domains) | Fully qualified domains the managed certificate covers and the load balancer serves, e.g. ["api.example.com"]. At least one is required; Google provisions one managed cert covering all of them. | `list(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Base name for the load balancer resources. Each resource appends a suffix (-ip, -neg, -backend, -cert, ...). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID that hosts the load balancer, certificate, and backend. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region of the Cloud Run service the serverless NEG targets, e.g. europe-west1. | `string` | n/a | yes |
| <a name="input_dns_managed_zone"></a> [dns\_managed\_zone](#input\_dns\_managed\_zone) | Optional Cloud DNS managed-zone name in var.project\_id. When set, the module creates an A record per domain pointing at the load balancer IP. Null leaves DNS to the operator (the module still outputs the IP to point records at). | `string` | `null` | no |
| <a name="input_dns_ttl"></a> [dns\_ttl](#input\_dns\_ttl) | TTL in seconds for the DNS A records, used only when dns\_managed\_zone is set. | `number` | `300` | no |
| <a name="input_enable_cdn"></a> [enable\_cdn](#input\_enable\_cdn) | Enable Cloud CDN on the backend service. Default false; turn on for cacheable public content. | `bool` | `false` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource this module creates (merged with the provider default\_labels; resource-specific labels win). | `map(string)` | `{}` | no |
| <a name="input_security_policy_id"></a> [security\_policy\_id](#input\_security\_policy\_id) | Optional Cloud Armor security policy ID (self\_link) to attach to the backend service. Null leaves the backend without an edge WAF, so set this for any internet-facing service that needs rate limiting or OWASP rules. | `string` | `null` | no |
| <a name="input_ssl_policy_id"></a> [ssl\_policy\_id](#input\_ssl\_policy\_id) | Optional SSL policy ID (self\_link) for the HTTPS proxy. Null uses Google's default negotiation; set a MODERN or RESTRICTED policy to pin a minimum TLS version. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_service_id"></a> [backend\_service\_id](#output\_backend\_service\_id) | ID of the backend service, for attaching further Cloud Armor policies or backends. |
| <a name="output_certificate_id"></a> [certificate\_id](#output\_certificate\_id) | ID of the Google-managed SSL certificate. Provisioning completes only after DNS resolves to the load balancer IP. |
| <a name="output_https_forwarding_rule_id"></a> [https\_forwarding\_rule\_id](#output\_https\_forwarding\_rule\_id) | ID of the HTTPS (443) global forwarding rule. |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | The reserved global anycast IP of the load balancer. Point DNS A records here if dns\_managed\_zone is not set. |
| <a name="output_ip_name"></a> [ip\_name](#output\_ip\_name) | Name of the reserved global address resource. |
| <a name="output_managed_domains"></a> [managed\_domains](#output\_managed\_domains) | Domains the managed certificate covers. |
<!-- END_TF_DOCS -->
