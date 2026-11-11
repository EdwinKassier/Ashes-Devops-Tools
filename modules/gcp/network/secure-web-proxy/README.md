# Secure Web Proxy Module (preview, opt-in)

> **Preview.** Not yet validated against a real apply. Nothing in the landing
> zone creates it unless you opt in (`secure_web_proxy.enabled` on
> `stages/net-hub` / `stages/network-hub`).

This module creates a regional [Secure Web Proxy](https://cloud.google.com/secure-web-proxy/docs/overview)
for central egress control with an FQDN allowlist:

- a `SECURE_WEB_GATEWAY` gateway in explicit mode (clients set `HTTPS_PROXY`) or next-hop mode
- a gateway security policy that allows the hosts in `allowed_fqdns` (one URL list, one ALLOW
  rule at priority 1000) and denies everything else
- optional extra CEL rules (`additional_rules`)
- optionally, the proxy-only subnet (`REGIONAL_MANAGED_PROXY`) the gateway needs
- optionally, a Private Service Connect service attachment that publishes the proxy to
  other VPC networks, accepting only the listed consumer projects

## How spokes use a hub proxy

Peered VPC networks do not reliably reach a proxy in another VPC, and next-hop routes
through a peering are not supported for it. The landing zone therefore uses the PSC model
Google documents for multi-VPC deployments:

1. The hub publishes the proxy (`create_service_attachment = true`).
2. Each spoke creates a PSC endpoint in its own VPC (`stages/net-spoke` `egress_proxy`).
3. Workloads set `HTTPS_PROXY=http://<endpoint address>:<port>`. The spoke drops its
   private tier from Cloud NAT, so the proxy is the only internet path for that tier.

Limits: traffic through PSC is source-NATed, so rules cannot match on client IP (match
on host, or on tags or service accounts in explicit mode inside the hub VPC). Without
TLS inspection the proxy sees the host (CONNECT target / SNI), not HTTPS paths. The
gateway creates its own Cloud Router and NAT for egress
(`delete_swg_autogen_router_on_destroy` removes them with the last gateway).

## Usage

```hcl
module "secure_web_proxy" {
  source = "../secure-web-proxy"

  project_id = "my-hub-project"
  name       = "hub-swp"
  region     = "us-central1"
  network    = "projects/my-hub-project/global/networks/hub-vpc"
  subnetwork = "projects/my-hub-project/regions/us-central1/subnetworks/hub-private"

  allowed_fqdns = ["*.github.com", "pypi.org"]

  create_proxy_only_subnet = true
  proxy_only_subnet_cidr   = "10.0.254.0/23"

  create_service_attachment = true
  psc_nat_subnet_cidr       = "10.0.253.0/24"
  consumer_accept_projects  = ["111111111111"]
}
```

<!-- BEGIN_TF_DOCS -->
Copyright 2026 Ashes

# Secure Web Proxy (preview, opt-in)

A regional Secure Web Proxy (Cloud Secure Web Proxy, an Envoy-based egress
proxy) with a gateway security policy that allows an FQDN allowlist and
denies everything else. Optionally creates the proxy-only subnet it needs
and publishes the gateway through a Private Service Connect service
attachment, so other VPC networks reach one central proxy through a PSC
endpoint each.

Explicit mode: clients set HTTP\_PROXY / HTTPS\_PROXY to the gateway (or PSC
endpoint) address. Next-hop mode: the caller adds routes with the gateway
address as next hop (same VPC and region only).

PREVIEW: not yet validated against a real apply. TLS inspection is not
configured, so rules match on the host (SNI / CONNECT target), not on paths
of HTTPS requests.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name =
	network =
	project_id =
	region =
	subnetwork =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.10.0 |



## Resources

The following resources are created:


- resource.google_compute_service_attachment.this (modules/gcp/network/secure-web-proxy/main.tf#L126)
- resource.google_compute_subnetwork.proxy_only (modules/gcp/network/secure-web-proxy/main.tf#L28)
- resource.google_compute_subnetwork.psc_nat (modules/gcp/network/secure-web-proxy/main.tf#L115)
- resource.google_network_security_gateway_security_policy.this (modules/gcp/network/secure-web-proxy/main.tf#L50)
- resource.google_network_security_gateway_security_policy_rule.additional (modules/gcp/network/secure-web-proxy/main.tf#L71)
- resource.google_network_security_gateway_security_policy_rule.allowlist (modules/gcp/network/secure-web-proxy/main.tf#L57)
- resource.google_network_security_url_lists.allowlist (modules/gcp/network/secure-web-proxy/main.tf#L40)
- resource.google_network_services_gateway.this (modules/gcp/network/secure-web-proxy/main.tf#L86)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Base name of the gateway. The policy, URL list, subnets and service attachment derive their names from it. | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | VPC network ID the gateway serves, in the form projects/<project>/global/networks/<name>. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project that hosts the proxy. Secure Web Proxy can only be deployed in a VPC host project, not a Shared VPC service project. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region of the proxy. Secure Web Proxy is regional: clients in other regions need global access on their side (PSC endpoint) or a proxy per region. | `string` | n/a | yes |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | Subnetwork ID the gateway address is allocated from, in the form projects/<project>/regions/<region>/subnetworks/<name>. It must be in var.region. | `string` | n/a | yes |
| <a name="input_additional_rules"></a> [additional\_rules](#input\_additional\_rules) | Extra gateway security policy rules, keyed by rule name: priority (lower wins; 1000 is taken by the allowlist rule), action ALLOW or DENY, a CEL session\_matcher (for example "host() == 'example.com'" or "source.matchServiceAccount('sa@project.iam.gserviceaccount.com')"), an optional CEL application\_matcher, description and enabled. | <pre>map(object({<br/>    priority            = number<br/>    action              = string<br/>    session_matcher     = string<br/>    application_matcher = optional(string)<br/>    description         = optional(string)<br/>    enabled             = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_address"></a> [address](#input\_address) | Static internal IPv4 address of the gateway inside var.subnetwork. Null (default) lets Google allocate one (read it from the gateway\_address output). | `string` | `null` | no |
| <a name="input_allowed_fqdns"></a> [allowed\_fqdns](#input\_allowed\_fqdns) | Egress allowlist: host names ("api.example.com"), wildcard hosts ("*.example.com") or host/path patterns the proxy lets through. They become one URL list and one ALLOW rule at priority 1000. Everything that no rule allows is denied. Empty (default) = no allowlist rule, so the proxy denies all traffic unless additional\_rules allow some. | `list(string)` | `[]` | no |
| <a name="input_certificate_urls"></a> [certificate\_urls](#input\_certificate\_urls) | Certificate Manager certificate URLs the gateway presents on TLS connections to the proxy itself. Empty (default) = none. | `list(string)` | `[]` | no |
| <a name="input_consumer_accept_projects"></a> [consumer\_accept\_projects](#input\_consumer\_accept\_projects) | Project IDs or numbers whose PSC endpoints the service attachment accepts (ACCEPT\_MANUAL). Only these projects can send traffic through the proxy. Required (non-empty) when create\_service\_attachment is true. | `list(string)` | `[]` | no |
| <a name="input_consumer_connection_limit"></a> [consumer\_connection\_limit](#input\_consumer\_connection\_limit) | Maximum PSC endpoints each accepted project may connect. | `number` | `10` | no |
| <a name="input_create_proxy_only_subnet"></a> [create\_proxy\_only\_subnet](#input\_create\_proxy\_only\_subnet) | Create the regional proxy-only subnet (purpose REGIONAL\_MANAGED\_PROXY, role ACTIVE) the gateway needs. False (default) = one already exists in the network and region (it is shared with regional Envoy load balancers, and a network can have only one active one per region). | `bool` | `false` | no |
| <a name="input_create_service_attachment"></a> [create\_service\_attachment](#input\_create\_service\_attachment) | Publish the gateway through a Private Service Connect service attachment, so other VPC networks (for example environment spokes) reach it through a PSC endpoint in their own VPC. Needs EXPLICIT\_ROUTING\_MODE, psc\_nat\_subnet\_cidr and consumer\_accept\_projects. Default false. | `bool` | `false` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the gateway. | `map(string)` | `{}` | no |
| <a name="input_ports"></a> [ports](#input\_ports) | Ports the gateway listens on. Clients send HTTP CONNECT (or plain HTTP) to <gateway address>:<port>. | `list(number)` | <pre>[<br/>  443<br/>]</pre> | no |
| <a name="input_proxy_only_subnet_cidr"></a> [proxy\_only\_subnet\_cidr](#input\_proxy\_only\_subnet\_cidr) | CIDR of the proxy-only subnet (Google recommends a /23). Required when create\_proxy\_only\_subnet is true. | `string` | `null` | no |
| <a name="input_psc_nat_subnet_cidr"></a> [psc\_nat\_subnet\_cidr](#input\_psc\_nat\_subnet\_cidr) | CIDR of the Private Service Connect NAT subnet (purpose PRIVATE\_SERVICE\_CONNECT) the service attachment source-NATs consumer traffic into. Required when create\_service\_attachment is true. Policy rules cannot match on the original client IP through PSC. | `string` | `null` | no |
| <a name="input_routing_mode"></a> [routing\_mode](#input\_routing\_mode) | EXPLICIT\_ROUTING\_MODE (default): clients use the proxy through HTTP\_PROXY / HTTPS\_PROXY. NEXT\_HOP\_ROUTING\_MODE: the caller adds routes with the gateway address as next hop, in the same VPC and region. A service attachment needs EXPLICIT\_ROUTING\_MODE. | `string` | `"EXPLICIT_ROUTING_MODE"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_gateway_address"></a> [gateway\_address](#output\_gateway\_address) | Internal address clients (or next-hop routes) send traffic to: var.address when set, else the address Google allocated (known after apply). |
| <a name="output_gateway_id"></a> [gateway\_id](#output\_gateway\_id) | ID of the Secure Web Proxy gateway (projects/<project>/locations/<region>/gateways/<name>). |
| <a name="output_gateway_ports"></a> [gateway\_ports](#output\_gateway\_ports) | Ports the gateway listens on. |
| <a name="output_gateway_security_policy_id"></a> [gateway\_security\_policy\_id](#output\_gateway\_security\_policy\_id) | ID of the gateway security policy. |
| <a name="output_proxy_only_subnet_id"></a> [proxy\_only\_subnet\_id](#output\_proxy\_only\_subnet\_id) | ID of the proxy-only subnet this module created, or null when create\_proxy\_only\_subnet is false. |
| <a name="output_service_attachment_id"></a> [service\_attachment\_id](#output\_service\_attachment\_id) | ID of the PSC service attachment (projects/<project>/regions/<region>/serviceAttachments/<name>) consumers target from their endpoint, or null when create\_service\_attachment is false. |
| <a name="output_url_list_id"></a> [url\_list\_id](#output\_url\_list\_id) | ID of the FQDN allowlist URL list, or null when allowed\_fqdns is empty. |
<!-- END_TF_DOCS -->
