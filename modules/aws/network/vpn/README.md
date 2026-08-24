# AWS Site-to-Site VPN Module

IPsec Site-to-Site VPN for hybrid connectivity to an on-premises network — the
AWS parity counterpart to GCP's `modules/gcp/network/vpn` (HA-VPN). Terminates
on either a **Transit Gateway** (recommended — centralized in the network
account) or a **Virtual Private Gateway**, and provisions AWS's two redundant
tunnels per connection with modern, secure IKEv2 / AES-GCM-256 defaults.

## Usage

```hcl
module "vpn" {
  source = "../../network/vpn"

  name                = "onprem-dc1"
  customer_gateway_ip = "203.0.113.10"

  attach_to          = "transit_gateway"
  transit_gateway_id = module.network_hub.transit_gateway_id

  # Dynamic (BGP) routing is the default; for static:
  # static_routes_only = true
  # static_routes      = ["10.0.0.0/8"]
}
```

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	customer_gateway_ip = 
	name = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_customer_gateway.this (modules/aws/network/vpn/main.tf#L6)
- resource.aws_vpn_connection.this (modules/aws/network/vpn/main.tf#L13)
- resource.aws_vpn_connection_route.this (modules/aws/network/vpn/main.tf#L46)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_customer_gateway_ip"></a> [customer\_gateway\_ip](#input\_customer\_gateway\_ip) | Public IP address of the on-premises (customer) VPN device. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the VPN resources (customer gateway, connection). | `string` | n/a | yes |
| <a name="input_attach_to"></a> [attach\_to](#input\_attach\_to) | Where to terminate the VPN on the AWS side: 'transit\_gateway' (set transit\_gateway\_id) or 'vpn\_gateway' (set vpn\_gateway\_id). | `string` | `"transit_gateway"` | no |
| <a name="input_customer_gateway_bgp_asn"></a> [customer\_gateway\_bgp\_asn](#input\_customer\_gateway\_bgp\_asn) | BGP ASN of the customer gateway (used for dynamic routing). | `number` | `65000` | no |
| <a name="input_enable_acceleration"></a> [enable\_acceleration](#input\_enable\_acceleration) | Enable AWS Global Accelerator for the VPN connection (requires a Transit Gateway attachment). | `bool` | `false` | no |
| <a name="input_static_routes"></a> [static\_routes](#input\_static\_routes) | Destination CIDR blocks for static routes (only used when static\_routes\_only = true). | `list(string)` | `[]` | no |
| <a name="input_static_routes_only"></a> [static\_routes\_only](#input\_static\_routes\_only) | Use static routing (true) instead of BGP dynamic routing (false). Dynamic (BGP) is preferred where the customer device supports it. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the VPN resources. | `map(string)` | `{}` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | Transit Gateway ID to attach the VPN connection to (required when attach\_to = transit\_gateway). | `string` | `null` | no |
| <a name="input_tunnel_inside_cidrs"></a> [tunnel\_inside\_cidrs](#input\_tunnel\_inside\_cidrs) | Optional list of /30 inside CIDRs for the two tunnels (link-local 169.254.0.0/16). Empty = AWS-assigned. | `list(string)` | `[]` | no |
| <a name="input_vpn_gateway_id"></a> [vpn\_gateway\_id](#input\_vpn\_gateway\_id) | Virtual Private Gateway (VGW) ID to attach the VPN connection to (required when attach\_to = vpn\_gateway). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_customer_gateway_id"></a> [customer\_gateway\_id](#output\_customer\_gateway\_id) | ID of the customer gateway. |
| <a name="output_tunnel1_address"></a> [tunnel1\_address](#output\_tunnel1\_address) | Public IP address of the first VPN tunnel (AWS side). |
| <a name="output_tunnel2_address"></a> [tunnel2\_address](#output\_tunnel2\_address) | Public IP address of the second VPN tunnel (AWS side). |
| <a name="output_vpn_connection_id"></a> [vpn\_connection\_id](#output\_vpn\_connection\_id) | ID of the Site-to-Site VPN connection. |
<!-- END_TF_DOCS -->
