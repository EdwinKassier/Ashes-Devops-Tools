# Network Hub Stage Module

Establishes the centralized networking architecture (Hub-and-Spoke topology).

## Purpose

- Creates the **Shared VPC** in a dedicated hub project
- Configures **Cloud DNS** hub for centralized name resolution
- Sets up **VPC Service Controls** perimeters (dry-run initially)
- Implements **Hierarchical Firewall Policies**
- Manages **Interconnect/VPN** gateways (if configured)

## Architecture

This module creates two core projects:
1. `net-hub`: Hosts the Shared VPC code
2. `dns-hub`: Hosts private DNS zones

## Composition

| Call | Source | Role |
|------|--------|------|
| `module.hub` | [`net-hub`](../net-hub/) | Hub Shared VPC, NAT, PSA, PSC, hierarchical firewall, hub VPC-SC perimeter |
| `module.dns_anchor` | [`dns-anchor`](../dns-anchor/) | DNS-anchor VPC and the `internal-root` private zone |
| `module.hub_cloud_armor` | [`network/cloud-armor`](../../network/cloud-armor/) | Hub WAF policy kept from the `stages/host` era |

Until this release the stage called the deprecated `stages/host` module twice
(`module.hub_network`, `module.dns_hub_network`). [`moved.tf`](./moved.tf)
migrates every object those calls held, so the first plan after upgrading
shows moves only. The hub perimeter key is now `hub_data_perimeter`: the old
`hub-data-perimeter` key failed the vpc-sc name validation, so no perimeter
can exist in state under it.

## Usage

```hcl
module "network_hub" {
  source = "../../modules/gcp/stages/network-hub"

  org_id          = "123456789"
  hub_project_id  = "my-org-net-hub"
  dns_project_id  = "my-org-dns-hub"

  # DNS Configuration
  internal_domain = "internal.mycompany.com"

  # Spoke project NUMBERS (not project ID strings) for VPC-SC perimeter membership.
  # The Access Context Manager API requires numeric project numbers; project ID
  # strings cause misleading "permission denied" errors at apply time.
  spoke_project_numbers = {
    "prod-app" = "123456789012"   # run: gcloud projects describe <id> --format='value(projectNumber)'
  }
}
```

## Security Features

- **Private Google Access**: Enforced on all subnets
- **VPC-SC**: Data exfiltration protection for sensitive services
- **Firewall**: Default deny ingress, strict egress

## Outputs

- `hub_vpc_self_link`: Self link of the hub VPC
- `hub_vpc_name`: Name of the hub VPC
- `dns_zone_name`: Name of the managed DNS zone
- `hub_dns_domain`: DNS name managed by the hub DNS project

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	default_region =
	dns_hub_vpc_cidr_block =
	dns_project_id =
	folders =
	hub_project_id =
	hub_vpc_cidr_block =
	org_id =
	project_prefix =
	spoke_project_numbers =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 7.0 |



## Modules


- dns_anchor - ../dns-anchor
- hub - ../net-hub
- hub_cloud_armor - ../../network/cloud-armor




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default GCP region for resources | `string` | n/a | yes |
| <a name="input_dns_hub_vpc_cidr_block"></a> [dns\_hub\_vpc\_cidr\_block](#input\_dns\_hub\_vpc\_cidr\_block) | CIDR block for the DNS hub VPC (e.g. "10.1.0.0/16"). Required — must not overlap with hub\_vpc\_cidr\_block. | `string` | n/a | yes |
| <a name="input_dns_project_id"></a> [dns\_project\_id](#input\_dns\_project\_id) | Project ID for the DNS hub | `string` | n/a | yes |
| <a name="input_folders"></a> [folders](#input\_folders) | Map of folder objects to attach policies to | <pre>map(object({<br/>    id           = string<br/>    name         = string<br/>    display_name = string<br/>  }))</pre> | n/a | yes |
| <a name="input_hub_project_id"></a> [hub\_project\_id](#input\_hub\_project\_id) | Project ID for the network hub | `string` | n/a | yes |
| <a name="input_hub_vpc_cidr_block"></a> [hub\_vpc\_cidr\_block](#input\_hub\_vpc\_cidr\_block) | CIDR block for the hub VPC (e.g. "10.0.0.0/16"). Required — set via IPAM or per-environment tfvars. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The GCP organization ID. Accepts either a bare numeric ID (e.g. '123456789012') as returned<br/>by data.google\_organization.org.org\_id, or the 'organizations/<id>' prefixed form.<br/>The module normalizes to the prefixed form internally before passing to VPC-SC. | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix used for project naming | `string` | n/a | yes |
| <a name="input_spoke_project_numbers"></a> [spoke\_project\_numbers](#input\_spoke\_project\_numbers) | Map of spoke project NUMBERS (not IDs) to include in the VPC-SC perimeter.<br/>The GCP Access Context Manager API requires numeric project numbers prefixed with<br/>"projects/". Project IDs (e.g. "myorg-dev-host-abc1") are rejected with a<br/>permission error that is misleading — always pass project numbers here.<br/><br/>Obtain with: gcloud projects describe <id> --format='value(projectNumber)'<br/>Or use module.projects.project\_numbers from the stages/projects module output. | `map(string)` | n/a | yes |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | When true (the default), protects hub and DNS VPC resources from accidental deletion via<br/>terraform destroy. Set to false only during a planned teardown.<br/>IMPORTANT: Set to false and apply before attempting to destroy the hub network stack. | `bool` | `true` | no |
| <a name="input_enable_ncc_hub"></a> [enable\_ncc\_hub](#input\_enable\_ncc\_hub) | Create a Network Connectivity Center hub in the hub project, with the hub VPC as its center spoke (and a producer spoke for its Private Service Access peering). Environment VPCs join it with connectivity = ncc. False (default) = VPC peering only. | `bool` | `false` | no |
| <a name="input_interconnects"></a> [interconnects](#input\_interconnects) | Cloud Interconnect VLAN attachments on the hub network (gcp.network.interconnect in config), keyed by attachment name (Dedicated or Partner). | <pre>map(object({<br/>    region            = string<br/>    interconnect_type = optional(string, "PARTNER")<br/>    router_name       = string<br/>    router_asn        = optional(number, 64512)<br/>    create_router     = optional(bool, true)<br/><br/>    # Dedicated interconnect settings<br/>    interconnect_self_link = optional(string)<br/>    vlan_tag               = optional(number)<br/>    bandwidth              = optional(string, "BPS_10G")<br/><br/>    # Partner interconnect settings<br/>    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")<br/><br/>    # Common settings<br/>    mtu           = optional(number, 1440)<br/>    admin_enabled = optional(bool, true)<br/>    encryption    = optional(string, "NONE")<br/><br/>    # BGP settings<br/>    create_bgp_peer    = optional(bool, true)<br/>    interface_ip_range = optional(string)<br/>    peer_ip_address    = optional(string)<br/>    peer_asn           = optional(number, 65000)<br/>    enable_bfd         = optional(bool, false)<br/><br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = optional(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_internal_domain"></a> [internal\_domain](#input\_internal\_domain) | Internal domain for private DNS zone (e.g., 'mycompany.com') | `string` | `"internal.local"` | no |
| <a name="input_ncc_preset_topology"></a> [ncc\_preset\_topology](#input\_ncc\_preset\_topology) | NCC hub preset topology: STAR (environment spokes reach the hub VPC, not each other; the peering-equivalent) or MESH (every spoke reaches every other). Immutable once the hub exists. | `string` | `"STAR"` | no |
| <a name="input_vpc_sc_access_policy_name"></a> [vpc\_sc\_access\_policy\_name](#input\_vpc\_sc\_access\_policy\_name) | Bare numeric ID of the existing organisation-level Access Context Manager access policy<br/>(e.g. '1234567890'). Required when the hub VPC-SC perimeter is enabled.<br/>Do NOT include the 'accessPolicies/' prefix. | `string` | `null` | no |
| <a name="input_vpc_sc_additional_restricted_services"></a> [vpc\_sc\_additional\_restricted\_services](#input\_vpc\_sc\_additional\_restricted\_services) | Extra service API hostnames to add to the hub data perimeter's restricted\_services,<br/>beyond the base set (storage/bigquery/cloudfunctions/run). Recommended additions once<br/>an automation ingress policy is in place: logging.googleapis.com, monitoring.googleapis.com,<br/>cloudkms.googleapis.com, secretmanager.googleapis.com, compute.googleapis.com,<br/>container.googleapis.com, pubsub.googleapis.com, spanner.googleapis.com, sqladmin.googleapis.com.<br/>Default [] = unchanged. PREVIEW (not yet validated against a real apply) against a real org — validate under dry-run first. | `list(string)` | `[]` | no |
| <a name="input_vpc_sc_dry_run_additional_restricted_services"></a> [vpc\_sc\_dry\_run\_additional\_restricted\_services](#input\_vpc\_sc\_dry\_run\_additional\_restricted\_services) | Services to TRIAL in a staged dry-run spec on top of the enforced hub perimeter (base set + vpc\_sc\_additional\_restricted\_services). Only meaningful when vpc\_sc\_enable\_dry\_run = false: status keeps enforcing, the dry-run spec logs what these extra services would block. Default null = no staged spec. | `list(string)` | `null` | no |
| <a name="input_vpc_sc_enable_dry_run"></a> [vpc\_sc\_enable\_dry\_run](#input\_vpc\_sc\_enable\_dry\_run) | When true (the default), the hub VPC-SC perimeter logs violations but does NOT block traffic (dry-run/simulation mode).<br/>When false, the perimeter is ENFORCED.<br/>Google recommends dry-run first: validate the violation logs, then promote to enforcement by setting this false.<br/>See docs/known-gaps.md. | `bool` | `true` | no |
| <a name="input_vpc_sc_ingress_identities"></a> [vpc\_sc\_ingress\_identities](#input\_vpc\_sc\_ingress\_identities) | Identities (e.g. "serviceAccount:terraform-admin@<admin-project>.iam.gserviceaccount.com")<br/>granted full ingress into the hub data perimeter — set this to the automation/TFC-run SA<br/>BEFORE expanding restricted\_services or the next enforced apply is blocked. Default [] =<br/>no ingress policy (unchanged). PREVIEW (not yet validated against a real apply) — validate under dry-run first. | `list(string)` | `[]` | no |
| <a name="input_vpn"></a> [vpn](#input\_vpn) | HA VPN to an on-premises or other-cloud peer gateway, off by default.<br/>tunnel\_count is 2 for HA (production) or 1 for testing. peer\_gateway\_ips<br/>lists the peer interface IPv4 addresses (one per tunnel). local\_ips and<br/>peer\_ips are the BGP link-local addresses. The pre-shared key is the separate<br/>write-only vpn\_shared\_secret\_wo input. site\_to\_site\_data\_transfer lets on-premises sites exchange traffic through the NCC hybrid spoke. With enable\_ncc\_hub, the tunnels also join the NCC hub as a hybrid spoke. | <pre>object({<br/>    enabled                    = optional(bool, false)<br/>    tunnel_count               = optional(number, 2)<br/>    router_asn                 = optional(number, 64512)<br/>    peer_asn                   = optional(number, 64513)<br/>    peer_gateway_ips           = optional(list(string), [])<br/>    local_ips                  = optional(list(string), ["169.254.0.1", "169.254.0.3"])<br/>    peer_ips                   = optional(list(string), ["169.254.0.2", "169.254.0.4"])<br/>    site_to_site_data_transfer = optional(bool, false)<br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = string<br/>    })), [])<br/>  })</pre> | `{}` | no |
| <a name="input_vpn_shared_secret_wo"></a> [vpn\_shared\_secret\_wo](#input\_vpn\_shared\_secret\_wo) | Write-only HA VPN pre-shared key: sent to the API at apply time, never stored in state or plan. Supply it from an ephemeral source (an ephemeral resource, or a TFC variable). Required when vpn.enabled is true. | `string` | `null` | no |
| <a name="input_vpn_shared_secret_wo_version"></a> [vpn\_shared\_secret\_wo\_version](#input\_vpn\_shared\_secret\_wo\_version) | Rotation counter for vpn\_shared\_secret\_wo. Write-only values are not diffed: increment this to push a changed key. | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_zone_name"></a> [dns\_zone\_name](#output\_dns\_zone\_name) | Name of the managed private DNS zone |
| <a name="output_hierarchical_firewall_association_targets"></a> [hierarchical\_firewall\_association\_targets](#output\_hierarchical\_firewall\_association\_targets) | Folders the hub SSH/RDP-from-internet deny policy is associated with (shared + every environment folder). |
| <a name="output_hub_dns_domain"></a> [hub\_dns\_domain](#output\_hub\_dns\_domain) | DNS suffix served by the hub DNS project |
| <a name="output_hub_nat_ips"></a> [hub\_nat\_ips](#output\_hub\_nat\_ips) | External NAT IP addresses allocated to the hub Cloud NAT gateway (null if integrated NAT is disabled) |
| <a name="output_hub_subnet_self_links"></a> [hub\_subnet\_self\_links](#output\_hub\_subnet\_self\_links) | Map of private subnet name to self\_link for the hub VPC — useful for Shared VPC service project attachments and peering configuration |
| <a name="output_hub_vpc_name"></a> [hub\_vpc\_name](#output\_hub\_vpc\_name) | Name of the hub VPC |
| <a name="output_hub_vpc_self_link"></a> [hub\_vpc\_self\_link](#output\_hub\_vpc\_self\_link) | Self link of the hub VPC |
| <a name="output_hybrid_connectivity"></a> [hybrid\_connectivity](#output\_hybrid\_connectivity) | Which hybrid connectivity is planned for the hub: vpn (HA VPN on), ncc\_vpn\_spoke (tunnels linked to the NCC hub) and the Cloud Interconnect attachment names. |
| <a name="output_interconnect_states"></a> [interconnect\_states](#output\_interconnect\_states) | State of each hub Cloud Interconnect attachment (empty when none are configured). |
| <a name="output_ncc_hub_id"></a> [ncc\_hub\_id](#output\_ncc\_hub\_id) | ID of the Network Connectivity Center hub environment spokes attach to, or null when enable\_ncc\_hub = false. |
| <a name="output_ncc_spoke_group"></a> [ncc\_spoke\_group](#output\_ncc\_spoke\_group) | NCC group environment spokes join (edge for STAR, default for MESH), or null when enable\_ncc\_hub = false. |
| <a name="output_ncc_vpn_spoke_id"></a> [ncc\_vpn\_spoke\_id](#output\_ncc\_vpn\_spoke\_id) | ID of the NCC hybrid spoke that links the hub HA VPN tunnels, or null unless both enable\_ncc\_hub and vpn.enabled. |
| <a name="output_vpn_gateway_ips"></a> [vpn\_gateway\_ips](#output\_vpn\_gateway\_ips) | The hub HA VPN gateway external IP addresses (give them to the on-premises peer), or null when vpn.enabled = false. |
<!-- END_TF_DOCS -->
