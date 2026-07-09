# transit-gateway

Segmented transit gateway hub for the SRA landing zone. The gateway disables its
implicit default route tables (`default_route_table_association` /
`default_route_table_propagation` = `disable`) and expresses segmentation
explicitly: one route table per segment (`prod`, `nonprod`, `inspection`,
`shared`), each VPC attachment associated with exactly one segment, and
reachability granted only by explicit propagations.

**prod/nonprod isolation** is enforced by *omitting* any prod->nonprod or
nonprod->prod propagation. Because there is no default route table to leak
routes, an absent propagation means no reachability. prod and nonprod each
propagate only to/from `shared`. Default routes steer prod/nonprod traffic to
the `inspection` attachment (for firewall inspection) via `var.routes`.

The transit gateway is shared organization-wide through AWS RAM
(`allow_external_principals = false`).

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_arn = 
	
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


- resource.aws_ec2_transit_gateway.this (modules/aws/transit-gateway/main.tf#L21)
- resource.aws_ec2_transit_gateway_route.this (modules/aws/transit-gateway/main.tf#L72)
- resource.aws_ec2_transit_gateway_route_table.this (modules/aws/transit-gateway/main.tf#L32)
- resource.aws_ec2_transit_gateway_route_table_association.this (modules/aws/transit-gateway/main.tf#L53)
- resource.aws_ec2_transit_gateway_route_table_propagation.this (modules/aws/transit-gateway/main.tf#L63)
- resource.aws_ec2_transit_gateway_vpc_attachment.this (modules/aws/transit-gateway/main.tf#L39)
- resource.aws_ram_principal_association.org (modules/aws/transit-gateway/main.tf#L93)
- resource.aws_ram_resource_association.tgw (modules/aws/transit-gateway/main.tf#L88)
- resource.aws_ram_resource_share.this (modules/aws/transit-gateway/main.tf#L83)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | ARN of the AWS Organization (or an OU) to grant access to the shared transit gateway via RAM. | `string` | n/a | yes |
| <a name="input_attachments"></a> [attachments](#input\_attachments) | VPC attachments keyed by attachment name. segment must be one of route\_tables. appliance\_mode enables symmetric routing (set true on the inspection attachment). | <pre>map(object({<br/>    vpc_id         = string<br/>    subnet_ids     = list(string)<br/>    segment        = string<br/>    appliance_mode = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "inspection": {<br/>    "appliance_mode": true,<br/>    "segment": "inspection",<br/>    "subnet_ids": [<br/>      "subnet-insp0a",<br/>      "subnet-insp0b"<br/>    ],<br/>    "vpc_id": "vpc-inspection0000000"<br/>  },<br/>  "nonprod": {<br/>    "segment": "nonprod",<br/>    "subnet_ids": [<br/>      "subnet-nonp0a",<br/>      "subnet-nonp0b"<br/>    ],<br/>    "vpc_id": "vpc-nonprod00000000"<br/>  },<br/>  "prod": {<br/>    "segment": "prod",<br/>    "subnet_ids": [<br/>      "subnet-prod0a",<br/>      "subnet-prod0b"<br/>    ],<br/>    "vpc_id": "vpc-prod00000000000"<br/>  }<br/>}</pre> | no |
| <a name="input_description"></a> [description](#input\_description) | Description applied to the transit gateway; also used as its Name tag. | `string` | `"org-tgw"` | no |
| <a name="input_propagations"></a> [propagations](#input\_propagations) | Route-table propagations keyed by a plan-known string (e.g. "prod->shared"). attachment names a var.attachments key; route\_table names a var.route\_tables entry. prod<->nonprod pairings are deliberately omitted to enforce isolation. | <pre>map(object({<br/>    attachment  = string<br/>    route_table = string<br/>  }))</pre> | <pre>{<br/>  "inspection->nonprod": {<br/>    "attachment": "inspection",<br/>    "route_table": "nonprod"<br/>  },<br/>  "inspection->prod": {<br/>    "attachment": "inspection",<br/>    "route_table": "prod"<br/>  },<br/>  "nonprod->shared": {<br/>    "attachment": "nonprod",<br/>    "route_table": "shared"<br/>  },<br/>  "prod->shared": {<br/>    "attachment": "prod",<br/>    "route_table": "shared"<br/>  }<br/>}</pre> | no |
| <a name="input_route_tables"></a> [route\_tables](#input\_route\_tables) | Segment route tables to create on the transit gateway. Each attachment associates with exactly one of these segments. | `list(string)` | <pre>[<br/>  "prod",<br/>  "nonprod",<br/>  "inspection",<br/>  "shared"<br/>]</pre> | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Static routes keyed by a plan-known string. cidr is the destination; attachment (a var.attachments key) is the next hop; blackhole drops the traffic. Set exactly one of attachment or blackhole per route. | <pre>map(object({<br/>    route_table = string<br/>    cidr        = string<br/>    attachment  = optional(string)<br/>    blackhole   = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "nonprod:default": {<br/>    "attachment": "inspection",<br/>    "cidr": "0.0.0.0/0",<br/>    "route_table": "nonprod"<br/>  },<br/>  "prod:default": {<br/>    "attachment": "inspection",<br/>    "cidr": "0.0.0.0/0",<br/>    "route_table": "prod"<br/>  }<br/>}</pre> | no |
| <a name="input_share_name"></a> [share\_name](#input\_share\_name) | Name of the RAM resource share used to share the transit gateway across the organization. | `string` | `"tgw-share"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_attachment_ids"></a> [attachment\_ids](#output\_attachment\_ids) | Map of attachment name to transit gateway VPC attachment ID. |
| <a name="output_route_table_ids"></a> [route\_table\_ids](#output\_route\_table\_ids) | Map of segment name to transit gateway route table ID. |
| <a name="output_tgw_id"></a> [tgw\_id](#output\_tgw\_id) | The ID of the transit gateway. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "transit_gateway" {
  source = "../../modules/aws/transit-gateway"

  org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
