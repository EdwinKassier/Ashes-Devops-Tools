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


- resource.aws_default_security_group.this (modules/aws/vpc/main.tf#L75)
- resource.aws_flow_log.this (modules/aws/vpc/main.tf#L80)
- resource.aws_subnet.this (modules/aws/vpc/main.tf#L55)
- resource.aws_vpc.this (modules/aws/vpc/main.tf#L40)
- resource.aws_vpc_endpoint.gateway (modules/aws/vpc/main.tf#L88)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | ARN of the S3 bucket (in the central log archive) that receives VPC flow logs. | `string` | n/a | yes |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to place subnets in. Only the first az\_count entries are used. | `list(string)` | <pre>[<br/>  "eu-west-2a",<br/>  "eu-west-2b",<br/>  "eu-west-2c"<br/>]</pre> | no |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of availability zones to spread each subnet tier across. Must not exceed the number of availability\_zones. | `number` | `2` | no |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | IPv4 CIDR used for subnet math (cidrsubnet). Also the literal VPC CIDR when ipam\_pool\_id is empty. When using IPAM, still set this to the CIDR IPAM will allocate so subnet layout is deterministic. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Whether to assign an Amazon-provided /56 IPv6 CIDR block to the VPC. | `bool` | `false` | no |
| <a name="input_gateway_endpoints"></a> [gateway\_endpoints](#input\_gateway\_endpoints) | AWS services to create Gateway VPC endpoints for (e.g. s3, dynamodb). | `list(string)` | <pre>[<br/>  "s3",<br/>  "dynamodb"<br/>]</pre> | no |
| <a name="input_ipam_pool_id"></a> [ipam\_pool\_id](#input\_ipam\_pool\_id) | IPAM pool ID to allocate the VPC CIDR from. Empty string uses the literal cidr\_block instead. | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | Name applied to the VPC and used as the prefix for subnet Name tags. | `string` | `"landing-zone"` | no |
| <a name="input_netmask_length"></a> [netmask\_length](#input\_netmask\_length) | Netmask length requested from the IPAM pool when ipam\_pool\_id is set. Ignored when using a literal cidr\_block. | `number` | `16` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region, used to build gateway endpoint service names (com.amazonaws.<region>.<service>). | `string` | `"eu-west-2"` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subnet tiers, keyed by tier name. newbits/number\_offset drive cidrsubnet(cidr\_block, newbits, number\_offset + az\_index); public toggles map\_public\_ip\_on\_launch. | <pre>map(object({<br/>    newbits       = number<br/>    number_offset = number<br/>    public        = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "isolated": {<br/>    "newbits": 8,<br/>    "number_offset": 16<br/>  },<br/>  "private": {<br/>    "newbits": 8,<br/>    "number_offset": 8<br/>  },<br/>  "public": {<br/>    "newbits": 8,<br/>    "number_offset": 0,<br/>    "public": true<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
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
