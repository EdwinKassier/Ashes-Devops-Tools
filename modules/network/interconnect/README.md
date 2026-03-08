# Cloud Interconnect Module

Creates Dedicated or Partner Interconnect attachments (VLANs) for high-bandwidth, low-latency hybrid connectivity.

## Features

- Support for both Dedicated and Partner Interconnect
- Automatic Cloud Router creation
- BGP peering with on-premises routers
- BFD for fast failover detection
- Custom route advertisement
- IPsec encryption support

## Usage

### Partner Interconnect

```hcl
module "partner_interconnect" {
  source = "../network/interconnect"

  project_id        = "my-project"
  region            = "us-central1"
  network           = module.vpc.network_self_link
  attachment_name   = "partner-interconnect-1"
  interconnect_type = "PARTNER"

  router_name = "interconnect-router"
  router_asn  = 64512

  edge_availability_domain = "AVAILABILITY_DOMAIN_1"

  # BGP configuration
  create_bgp_peer    = true
  interface_ip_range = "169.254.1.0/29"
  peer_ip_address    = "169.254.1.1"
  peer_asn           = 65000
}

# After provisioning, share the pairing_key output with your partner provider
```

### Dedicated Interconnect

```hcl
module "dedicated_interconnect" {
  source = "../network/interconnect"

  project_id        = "my-project"
  region            = "us-central1"
  network           = module.vpc.network_self_link
  attachment_name   = "dedicated-vlan-1"
  interconnect_type = "DEDICATED"

  router_name = "dedicated-router"
  router_asn  = 64512

  interconnect_self_link = "https://www.googleapis.com/compute/v1/projects/my-project/global/interconnects/my-interconnect"
  vlan_tag               = 1001
  bandwidth              = "BPS_10G"

  # BGP configuration with BFD
  create_bgp_peer    = true
  interface_ip_range = "169.254.2.0/30"
  peer_ip_address    = "169.254.2.1"
  peer_asn           = 65000
  enable_bfd         = true
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| project_id | GCP project ID | string | yes |
| region | Region for the attachment | string | yes |
| network | VPC network self_link | string | yes |
| attachment_name | Name for the VLAN attachment | string | yes |
| interconnect_type | DEDICATED or PARTNER | string | no |
| router_name | Cloud Router name | string | yes |
| router_asn | BGP ASN for Cloud Router | number | no |
| peer_ip_address | On-prem router IP | string | no |
| peer_asn | On-prem BGP ASN | number | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the attachment |
| self_link | The self_link of the attachment |
| pairing_key | Partner interconnect pairing key (sensitive) |
| state | Current attachment state |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Cloud Interconnect Module - Main Configuration

Creates Dedicated or Partner Interconnect attachments (VLANs) for
high-bandwidth, low-latency connectivity to on-premises networks.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	attachment_name = 
	network = 
	project_id = 
	region = 
	router_name = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_compute_interconnect_attachment.dedicated (modules/network/interconnect/main.tf#L45)
- resource.google_compute_interconnect_attachment.partner (modules/network/interconnect/main.tf#L69)
- resource.google_compute_router.router (modules/network/interconnect/main.tf#L18)
- resource.google_compute_router_interface.interface (modules/network/interconnect/main.tf#L100)
- resource.google_compute_router_peer.peer (modules/network/interconnect/main.tf#L115)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attachment_name"></a> [attachment\_name](#input\_attachment\_name) | Name for the interconnect attachment (VLAN) | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The VPC network self\_link or ID | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region for the interconnect attachment | `string` | n/a | yes |
| <a name="input_router_name"></a> [router\_name](#input\_router\_name) | Name of the Cloud Router | `string` | n/a | yes |
| <a name="input_admin_enabled"></a> [admin\_enabled](#input\_admin\_enabled) | Whether the VLAN attachment is enabled | `bool` | `true` | no |
| <a name="input_advertised_groups"></a> [advertised\_groups](#input\_advertised\_groups) | Advertised groups for the router (e.g., ALL\_SUBNETS) | `list(string)` | <pre>[<br/>  "ALL_SUBNETS"<br/>]</pre> | no |
| <a name="input_advertised_ip_ranges"></a> [advertised\_ip\_ranges](#input\_advertised\_ip\_ranges) | Custom IP ranges to advertise via BGP | <pre>list(object({<br/>    range       = string<br/>    description = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_advertised_route_priority"></a> [advertised\_route\_priority](#input\_advertised\_route\_priority) | Priority for advertised routes (lower = higher priority) | `number` | `100` | no |
| <a name="input_bandwidth"></a> [bandwidth](#input\_bandwidth) | Provisioned bandwidth for dedicated interconnect (e.g., BPS\_1G, BPS\_10G) | `string` | `"BPS_10G"` | no |
| <a name="input_bfd_min_receive_interval"></a> [bfd\_min\_receive\_interval](#input\_bfd\_min\_receive\_interval) | Minimum BFD receive interval in milliseconds | `number` | `1000` | no |
| <a name="input_bfd_min_transmit_interval"></a> [bfd\_min\_transmit\_interval](#input\_bfd\_min\_transmit\_interval) | Minimum BFD transmit interval in milliseconds | `number` | `1000` | no |
| <a name="input_bfd_multiplier"></a> [bfd\_multiplier](#input\_bfd\_multiplier) | BFD detection multiplier | `number` | `5` | no |
| <a name="input_bfd_session_initialization_mode"></a> [bfd\_session\_initialization\_mode](#input\_bfd\_session\_initialization\_mode) | BFD session initialization mode: ACTIVE, PASSIVE, or DISABLED | `string` | `"ACTIVE"` | no |
| <a name="input_candidate_subnets"></a> [candidate\_subnets](#input\_candidate\_subnets) | Candidate subnets for auto-assigned IP addresses (CIDR format) | `list(string)` | `null` | no |
| <a name="input_create_bgp_peer"></a> [create\_bgp\_peer](#input\_create\_bgp\_peer) | Whether to create BGP peering configuration | `bool` | `true` | no |
| <a name="input_create_router"></a> [create\_router](#input\_create\_router) | Whether to create a new Cloud Router | `bool` | `true` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the interconnect attachment | `string` | `"Managed by Terraform"` | no |
| <a name="input_edge_availability_domain"></a> [edge\_availability\_domain](#input\_edge\_availability\_domain) | Edge availability domain for partner interconnect (AVAILABILITY\_DOMAIN\_1 or AVAILABILITY\_DOMAIN\_2) | `string` | `"AVAILABILITY_DOMAIN_1"` | no |
| <a name="input_enable_bfd"></a> [enable\_bfd](#input\_enable\_bfd) | Enable BFD for fast failover detection | `bool` | `false` | no |
| <a name="input_encryption"></a> [encryption](#input\_encryption) | Encryption mode: NONE or IPSEC | `string` | `"NONE"` | no |
| <a name="input_interconnect_self_link"></a> [interconnect\_self\_link](#input\_interconnect\_self\_link) | Self-link of the Dedicated Interconnect (required for DEDICATED type) | `string` | `null` | no |
| <a name="input_interconnect_type"></a> [interconnect\_type](#input\_interconnect\_type) | Type of interconnect: DEDICATED or PARTNER | `string` | `"PARTNER"` | no |
| <a name="input_interface_ip_range"></a> [interface\_ip\_range](#input\_interface\_ip\_range) | IP range for the router interface (CIDR format, /29 or /30) | `string` | `null` | no |
| <a name="input_mtu"></a> [mtu](#input\_mtu) | Maximum Transmission Unit (MTU) for the attachment | `number` | `1440` | no |
| <a name="input_peer_asn"></a> [peer\_asn](#input\_peer\_asn) | BGP ASN of the on-premises router | `number` | `65000` | no |
| <a name="input_peer_ip_address"></a> [peer\_ip\_address](#input\_peer\_ip\_address) | IP address of the on-premises BGP peer | `string` | `null` | no |
| <a name="input_router_asn"></a> [router\_asn](#input\_router\_asn) | BGP ASN for the Cloud Router | `number` | `64512` | no |
| <a name="input_vlan_tag"></a> [vlan\_tag](#input\_vlan\_tag) | 802.1Q VLAN tag for dedicated interconnect (1-4094) | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_attachment"></a> [attachment](#output\_attachment) | The full interconnect attachment resource |
| <a name="output_bgp_peer"></a> [bgp\_peer](#output\_bgp\_peer) | The BGP peer resource |
| <a name="output_cloud_router_ip_address"></a> [cloud\_router\_ip\_address](#output\_cloud\_router\_ip\_address) | The Cloud Router's IP address on this interconnect |
| <a name="output_customer_router_ip_address"></a> [customer\_router\_ip\_address](#output\_customer\_router\_ip\_address) | The customer router's IP address |
| <a name="output_id"></a> [id](#output\_id) | The ID of the interconnect attachment |
| <a name="output_interface"></a> [interface](#output\_interface) | The router interface resource |
| <a name="output_name"></a> [name](#output\_name) | The name of the interconnect attachment |
| <a name="output_operational_status"></a> [operational\_status](#output\_operational\_status) | Operational status of the interconnect attachment |
| <a name="output_pairing_key"></a> [pairing\_key](#output\_pairing\_key) | The pairing key for partner interconnect (share with partner provider) |
| <a name="output_router"></a> [router](#output\_router) | The Cloud Router resource (if created) |
| <a name="output_router_name"></a> [router\_name](#output\_router\_name) | The name of the Cloud Router |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the interconnect attachment |
| <a name="output_state"></a> [state](#output\_state) | Current state of the interconnect attachment |
<!-- END_TF_DOCS -->