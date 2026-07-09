# aws-network-hub stage

Phase-2 orchestration wrapper that builds the centralized network hub **entirely
in the network account**. Unlike `aws-security`, this stage uses a **single
default `aws` provider** (no aliases): every child module and stage-level
resource runs in the same account and region.

Composed children:

- **ipam** (`ipam`) — hierarchical IPAM (top pool + one regional pool per
  enabled region) shared org-wide over RAM. App roots allocate their VPC CIDRs
  from the exported regional pool ids.
- **inspection_vpc** (`vpc`) — the inspection VPC. Its `firewall` tier hosts the
  Network Firewall endpoints and its `tgw` tier hosts the transit-gateway
  attachment (appliance mode).
- **egress_vpc** (`vpc`) — the centralized egress VPC. Its `public` tier hosts
  the NAT gateways, its `private` tier hosts the interface endpoints and Route 53
  resolver endpoints, and its `tgw` tier hosts the transit-gateway attachment.
- **stage-level NAT** — the `vpc` leaf module intentionally omits NAT, so the
  stage layers on one `aws_eip` + `aws_nat_gateway` per egress `public` subnet
  plus a private route table whose `0.0.0.0/0` route egresses through NAT.
- **transit_gateway** (`transit-gateway`) — a segmented TGW with `prod`,
  `nonprod`, `inspection` and `shared` route tables. The inspection attachment
  propagates into `prod`/`nonprod`; the egress attachment propagates into
  `shared`. The `prod` and `nonprod` default routes (`0.0.0.0/0`) point at the
  inspection attachment so all egress/east-west traffic is centrally inspected.
- **network_firewall** (`network-firewall`) — stateful inspection deployed into
  the inspection VPC's `firewall` subnets. Cost-gated via
  `enable_network_firewall`.
- **vpc_endpoints** (`vpc-endpoints`) — centralized interface endpoints (and the
  optional shared private hosted zone) in the egress VPC's `private` subnets,
  scoped to the organization via `org_id`.
- **route53_resolver** (`route53-resolver`) — inbound/outbound resolver
  endpoints, DNS firewall, query logging, and the org-wide Route 53 Profile,
  associated with the egress VPC.
- **network_access_analyzer** (`network-access-analyzer`) — optional
  segmentation-intent scope, off by default (`enable_network_access_analyzer`).

### Subnet tier layout

Each VPC is a `/16`; tiers are `/24`s (`newbits = 8`) with `number_offset` in
units of one `/24`, spread over `az_count` AZs. Offsets are multiples of 8 so
per-AZ subnets within and across tiers never overlap:

| VPC | firewall | public | tgw | private |
|-----|----------|--------|-----|---------|
| inspection | `@0` | — | `@8` | `@16` |
| egress | — | `@0` | `@8` | `@16` |

The stage exports the cross-root network contract consumed by downstream roots:
`tgw_id`, `ipam_pool_ids`, `inspection_vpc_id`, `egress_vpc_id`,
`resolver_profile_id`, and `interface_endpoint_phz_id`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	flow_log_destination_arn = 
	log_bucket_name = 
	org_arn = 
	org_id = 
	
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

## Modules


- egress_vpc - ../../aws/vpc
- inspection_vpc - ../../aws/vpc
- ipam - ../../aws/ipam
- network_access_analyzer - ../../aws/network-access-analyzer
- network_firewall - ../../aws/network-firewall
- route53_resolver - ../../aws/route53-resolver
- transit_gateway - ../../aws/transit-gateway
- vpc_endpoints - ../../aws/vpc-endpoints


## Resources

The following resources are created:


- resource.aws_eip.nat (modules/stages/aws-network-hub/main.tf#L112)
- resource.aws_nat_gateway.this (modules/stages/aws-network-hub/main.tf#L120)
- resource.aws_route.egress_default (modules/stages/aws-network-hub/main.tf#L140)
- resource.aws_route_table.egress_private (modules/stages/aws-network-hub/main.tf#L134)
- resource.aws_route_table_association.egress_private (modules/stages/aws-network-hub/main.tf#L146)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | ARN of the S3 bucket (in the central log archive) that receives VPC flow logs and Route 53 resolver query logs. | `string` | n/a | yes |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | Name of the S3 bucket that receives Network Firewall flow logs. | `string` | n/a | yes |
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | ARN of the AWS Organization (arn:aws:organizations::<mgmt-account>:organization/o-xxxx) used as the RAM principal so the IPAM pools, transit gateway, and Route 53 Profile are shared org-wide. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations org id (o-xxxxxxxxxx) used to scope centralized VPC-endpoint access to this organization. | `string` | n/a | yes |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to spread each subnet tier across. Only the first az\_count entries are used. | `list(string)` | <pre>[<br/>  "eu-west-2a",<br/>  "eu-west-2b"<br/>]</pre> | no |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions IPAM operates in. Each becomes an operating region on the IPAM and gets its own regional pool. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the network hub is deployed in. Used for the inspection/egress VPCs, gateway/interface endpoint service names, and NAT placement. | `string` | `"eu-west-2"` | no |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of availability zones to spread each subnet tier across. | `number` | `2` | no |
| <a name="input_egress_cidr"></a> [egress\_cidr](#input\_egress\_cidr) | IPv4 CIDR of the centralized egress VPC that hosts the NAT gateways, interface endpoints, and Route 53 resolver endpoints. | `string` | `"10.1.0.0/16"` | no |
| <a name="input_enable_network_access_analyzer"></a> [enable\_network\_access\_analyzer](#input\_enable\_network\_access\_analyzer) | Whether to create the Network Access Analyzer scope that flags segmentation-intent violations. Off by default. | `bool` | `false` | no |
| <a name="input_enable_network_firewall"></a> [enable\_network\_firewall](#input\_enable\_network\_firewall) | Whether to deploy the Network Firewall in the inspection VPC. COST TOGGLE: bills per endpoint-hour plus per-GB processed. | `bool` | `true` | no |
| <a name="input_inspection_cidr"></a> [inspection\_cidr](#input\_inspection\_cidr) | IPv4 CIDR of the inspection VPC that hosts the Network Firewall endpoints and its transit-gateway attachment. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_private_hosted_zone_name"></a> [private\_hosted\_zone\_name](#input\_private\_hosted\_zone\_name) | Name of the shared Route 53 private hosted zone for split-horizon DNS in the egress VPC. Empty string skips creating the zone. | `string` | `""` | no |
| <a name="input_regional_cidrs"></a> [regional\_cidrs](#input\_regional\_cidrs) | Map of region to the CIDR each regional IPAM pool provisions. Every CIDR should fall within top\_cidr. | `map(string)` | <pre>{<br/>  "eu-west-2": "10.0.0.0/12"<br/>}</pre> | no |
| <a name="input_top_cidr"></a> [top\_cidr](#input\_top\_cidr) | CIDR of the top-level supernet owned by the top IPAM pool. | `string` | `"10.0.0.0/8"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_egress_vpc_id"></a> [egress\_vpc\_id](#output\_egress\_vpc\_id) | The ID of the centralized egress VPC that hosts NAT, interface endpoints, and resolver endpoints. |
| <a name="output_inspection_vpc_id"></a> [inspection\_vpc\_id](#output\_inspection\_vpc\_id) | The ID of the inspection VPC that hosts the Network Firewall. |
| <a name="output_interface_endpoint_phz_id"></a> [interface\_endpoint\_phz\_id](#output\_interface\_endpoint\_phz\_id) | Zone ID of the shared private hosted zone fronting the interface endpoints, or null when no zone was created. |
| <a name="output_ipam_pool_ids"></a> [ipam\_pool\_ids](#output\_ipam\_pool\_ids) | Map of region to the ID of its regional IPAM pool, consumed by app roots to allocate VPC CIDRs. |
| <a name="output_resolver_profile_id"></a> [resolver\_profile\_id](#output\_resolver\_profile\_id) | The ID of the Route 53 Profile shared org-wide over RAM. |
| <a name="output_tgw_id"></a> [tgw\_id](#output\_tgw\_id) | The ID of the transit gateway (the network cross-root routing contract). |
<!-- END_TF_DOCS -->
