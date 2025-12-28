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
