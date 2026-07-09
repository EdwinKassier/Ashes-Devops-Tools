# vpc-endpoints

Centralized interface VPC endpoints plus a shared private hosted zone for the
SRA landing zone. Interface endpoints (PrivateLink ENIs) for the common
control-plane services (`ec2`, `ssm`, `ssmmessages`, `ec2messages`, `kms`,
`logs`, `sts`) are created **once** in the central network-hub VPC and reached
by spoke VPCs over the transit gateway, avoiding per-spoke endpoint sprawl and
cost.

Each endpoint policy is scoped to the AWS Organization via the
`aws:PrincipalOrgID` condition, so only principals within `var.org_id` may use
the endpoints.

For centralized-endpoint DNS to resolve from the spokes (split-horizon), the
private DNS names must be served by a shared Route 53 private hosted zone
associated with each consuming VPC. This module manages that zone (when
`private_hosted_zone_name` is set). Cross-account VPC association
(`aws_route53_vpc_association_authorization` + RAM) is an extension layered on
by the network-hub stage and is intentionally out of scope for this leaf module.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_id = 
	region = 
	vpc_id = 
	
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


- resource.aws_route53_zone.shared (modules/aws/vpc-endpoints/main.tf#L44)
- resource.aws_vpc_endpoint.interface (modules/aws/vpc-endpoints/main.tf#L15)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations org id (o-xxxxxxxxxx) used in the endpoint policy aws:PrincipalOrgID condition to scope access to this organization. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region, used to build interface endpoint service names (com.amazonaws.<region>.<service>). | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the central hub VPC that hosts the interface endpoints and the shared private hosted zone. | `string` | n/a | yes |
| <a name="input_interface_services"></a> [interface\_services](#input\_interface\_services) | AWS services to create centralized Interface VPC endpoints for. Service names are built as com.amazonaws.<region>.<service>. | `list(string)` | <pre>[<br/>  "ec2",<br/>  "ssm",<br/>  "ssmmessages",<br/>  "ec2messages",<br/>  "kms",<br/>  "logs",<br/>  "sts"<br/>]</pre> | no |
| <a name="input_private_hosted_zone_name"></a> [private\_hosted\_zone\_name](#input\_private\_hosted\_zone\_name) | Name of the shared Route 53 private hosted zone for split-horizon DNS. Empty string skips creating the zone. | `string` | `""` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs to associate with the interface endpoint ENIs. | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs (one per AZ, in the hub VPC) to place the interface endpoint ENIs in. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_endpoint_ids"></a> [endpoint\_ids](#output\_endpoint\_ids) | Map of interface service name to the created VPC endpoint ID. |
| <a name="output_phz_id"></a> [phz\_id](#output\_phz\_id) | Zone ID of the shared private hosted zone, or null when no zone was created. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "vpc_endpoints" {
  source = "../../modules/aws/vpc-endpoints"

  vpc_id             = module.hub_vpc.vpc_id
  region             = "eu-west-2"
  org_id             = data.aws_organizations_organization.this.id
  subnet_ids         = module.hub_vpc.subnet_ids_by_tier["private"]
  security_group_ids = [module.endpoint_sg.security_group_id]

  # Shared private hosted zone for split-horizon DNS.
  private_hosted_zone_name = "internal.example.com"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
