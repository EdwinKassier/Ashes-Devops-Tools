# vpc

Data-driven VPC for the SRA landing zone. Subnets are described by tier in
`var.subnets` (tier -> `{newbits, number_offset, public}`) rather than a fixed
role enum, and one subnet is built per tier per AZ by carving CIDRs from the VPC
supernet with `cidrsubnet()`. The default security group is restricted to
deny-all, VPC flow logs are shipped to the central log archive, and Gateway
endpoints (S3, DynamoDB) keep that traffic on the AWS backbone.

NAT/egress subnets, firewall subnets, route tables, and transit-gateway wiring
are composed by the aws-network-hub STAGE, not by this leaf module.

When `ipam_pool_id` is set the VPC CIDR is allocated from IPAM, but `cidr_block`
must still be set to the intended CIDR so subnet math is deterministic (an
IPAM-allocated CIDR is unknown at plan time).

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	flow_log_destination_arn =
	region =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_default_security_group.this (modules/aws/network/vpc/main.tf#L118)
- resource.aws_flow_log.this (modules/aws/network/vpc/main.tf#L125)
- resource.aws_internet_gateway.this (modules/aws/network/vpc/main.tf#L176)
- resource.aws_route.public_internet (modules/aws/network/vpc/main.tf#L184)
- resource.aws_route.this (modules/aws/network/vpc/main.tf#L195)
- resource.aws_route_table.this (modules/aws/network/vpc/main.tf#L156)
- resource.aws_route_table_association.this (modules/aws/network/vpc/main.tf#L167)
- resource.aws_subnet.this (modules/aws/network/vpc/main.tf#L98)
- resource.aws_vpc.this (modules/aws/network/vpc/main.tf#L81)
- resource.aws_vpc_endpoint.gateway (modules/aws/network/vpc/main.tf#L135)
- resource.aws_vpc_endpoint_route_table_association.gateway (modules/aws/network/vpc/main.tf#L145)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | ARN of the S3 bucket (in the central log archive) that receives VPC flow logs. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region, used to build gateway endpoint service names (com.amazonaws.<region>.<service>). | `string` | n/a | yes |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to place subnets in. Only the first az\_count entries are used. | `list(string)` | <pre>[<br/>  "eu-west-2a",<br/>  "eu-west-2b",<br/>  "eu-west-2c"<br/>]</pre> | no |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of availability zones to spread each subnet tier across. Must not exceed the number of availability\_zones. | `number` | `2` | no |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | IPv4 CIDR used for subnet math (cidrsubnet). Also the VPC CIDR: literal when ipam\_pool\_id is empty, otherwise the exact block requested from the IPAM pool. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_create_internet_gateway"></a> [create\_internet\_gateway](#input\_create\_internet\_gateway) | Whether this module creates an internet gateway. When true, every public tier (public = true) route table gets a 0.0.0.0/0 default route to it. | `bool` | `false` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Whether to assign an Amazon-provided /56 IPv6 CIDR block to the VPC. | `bool` | `false` | no |
| <a name="input_gateway_endpoint_tiers"></a> [gateway\_endpoint\_tiers](#input\_gateway\_endpoint\_tiers) | Subnet tiers whose route tables the gateway endpoints are associated with. null (default) associates them with every non-public tier. | `list(string)` | `null` | no |
| <a name="input_gateway_endpoints"></a> [gateway\_endpoints](#input\_gateway\_endpoints) | AWS services to create Gateway VPC endpoints for (e.g. s3, dynamodb). | `list(string)` | <pre>[<br/>  "s3",<br/>  "dynamodb"<br/>]</pre> | no |
| <a name="input_ipam_pool_id"></a> [ipam\_pool\_id](#input\_ipam\_pool\_id) | IPAM pool ID the VPC allocates from. When set, the VPC requests exactly cidr\_block from the pool; empty string uses cidr\_block as a static CIDR. Adding a pool to an existing static VPC forces replacement. | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | Name applied to the VPC and used as the prefix for subnet Name tags. | `string` | `"landing-zone"` | no |
| <a name="input_netmask_length"></a> [netmask\_length](#input\_netmask\_length) | Retained for compatibility and ignored: the VPC requests the explicit cidr\_block from the IPAM pool, so no netmask length is sent. | `number` | `16` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Static routes keyed by subnet tier; each route is added to EVERY AZ route table of that tier. Set exactly one target per route (e.g. transit\_gateway\_id for spoke default routing to the hub). Per-AZ targets (such as per-AZ NAT gateways) should instead be added by the caller against route\_table\_ids\_by\_tier. | <pre>map(list(object({<br/>    destination_cidr_block    = string<br/>    transit_gateway_id        = optional(string)<br/>    nat_gateway_id            = optional(string)<br/>    gateway_id                = optional(string)<br/>    vpc_endpoint_id           = optional(string)<br/>    network_interface_id      = optional(string)<br/>    vpc_peering_connection_id = optional(string)<br/>  })))</pre> | `{}` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subnet tiers, keyed by tier name. newbits/number\_offset drive cidrsubnet(cidr\_block, newbits, number\_offset + az\_index); public toggles map\_public\_ip\_on\_launch. | <pre>map(object({<br/>    newbits       = number<br/>    number_offset = number<br/>    public        = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "isolated": {<br/>    "newbits": 8,<br/>    "number_offset": 16<br/>  },<br/>  "private": {<br/>    "newbits": 8,<br/>    "number_offset": 8<br/>  },<br/>  "public": {<br/>    "newbits": 8,<br/>    "number_offset": 0,<br/>    "public": true<br/>  }<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged under the per-resource Name/Tier tags). Org-wide tags (CostCenter, Environment, Owner, ...) normally come from the provider default\_tags; use this for module-specific additions. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_gateway_endpoint_ids"></a> [gateway\_endpoint\_ids](#output\_gateway\_endpoint\_ids) | Map of gateway endpoint service name (e.g. s3, dynamodb) to its VPC endpoint ID. |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | ID of the internet gateway, or null when create\_internet\_gateway is false. |
| <a name="output_route_table_ids_by_tier"></a> [route\_table\_ids\_by\_tier](#output\_route\_table\_ids\_by\_tier) | Map of subnet tier name to the list of route table IDs for that tier (one per AZ). Element order matches subnet\_ids\_by\_tier, so index i of both lists is the same AZ. |
| <a name="output_subnet_ids_by_tier"></a> [subnet\_ids\_by\_tier](#output\_subnet\_ids\_by\_tier) | Map of subnet tier name to the list of subnet IDs created for that tier (one per AZ). |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | The IPv4 CIDR used for the VPC and subnet math. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "vpc" {
  source = "../../modules/aws/vpc"

  region                   = "eu-west-2"
  flow_log_destination_arn = "arn:aws:s3:::my-log-archive-bucket"

  # Optional: allocate the VPC CIDR from a regional IPAM pool. cidr_block still
  # describes the subnet layout.
  # ipam_pool_id   = module.ipam.regional_pool_ids["eu-west-2"]
  # netmask_length = 16
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
