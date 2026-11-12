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

An endpoint's own private DNS is a hidden zone that only the endpoint VPC sees.
With `enable_shared_private_dns = true` the module turns it off and serves each
regional name (`<service>.<region>.amazonaws.com`) from a private hosted zone
with an alias A record to the endpoint. Pass the `shared_dns_zone_arns` output
to a Route 53 Profile (`route53-resolver` input `profile_hosted_zone_arns`) and
every VPC that associates the profile resolves the service names to the
central endpoints. Use it only for services whose private DNS name has that
form.

With `security_group_ids` empty and `allowed_cidrs` set, the module owns the
endpoint security group: HTTPS (443) in from `allowed_cidrs`, no egress rule.
With neither, the endpoints get the VPC default security group, which the
`vpc` module strips to deny-all.

The optional `private_hosted_zone_name` zone is a separate, empty private
hosted zone associated with the endpoint VPC.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_route53_record.endpoint (modules/aws/network/vpc-endpoints/main.tf#L114)
- resource.aws_route53_zone.endpoint (modules/aws/network/vpc-endpoints/main.tf#L99)
- resource.aws_route53_zone.shared (modules/aws/network/vpc-endpoints/main.tf#L80)
- resource.aws_security_group.endpoints (modules/aws/network/vpc-endpoints/main.tf#L20)
- resource.aws_vpc_endpoint.interface (modules/aws/network/vpc-endpoints/main.tf#L46)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations org id (o-xxxxxxxxxx) used in the endpoint policy aws:PrincipalOrgID condition to scope access to this organization. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region, used to build interface endpoint service names (com.amazonaws.<region>.<service>). | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the central hub VPC that hosts the interface endpoints and the shared private hosted zone. | `string` | n/a | yes |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDRs that may reach the interface endpoints on 443 when security\_group\_ids is empty (the module then owns the group). Use the org supernet for centralized endpoints. Empty with no security\_group\_ids = the VPC default security group. | `list(string)` | `[]` | no |
| <a name="input_enable_shared_private_dns"></a> [enable\_shared\_private\_dns](#input\_enable\_shared\_private\_dns) | Serve each endpoint's regional name (<service>.<region>.amazonaws.com) from a private hosted zone with an alias record, instead of the endpoint's own private DNS, so other VPCs (through a Route 53 Profile) resolve the central endpoint. Only for services whose private DNS name is <service>.<region>.amazonaws.com. Default false. | `bool` | `false` | no |
| <a name="input_endpoint_policy_json"></a> [endpoint\_policy\_json](#input\_endpoint\_policy\_json) | Optional override for the interface-endpoint policy (a JSON document). When null (default), the module applies an org-scoped allow-all policy gated by aws:PrincipalOrgID and relies on IAM for authorization. Supply a scoped policy to enforce per-service least privilege on the shared endpoints. | `string` | `null` | no |
| <a name="input_interface_services"></a> [interface\_services](#input\_interface\_services) | AWS services to create centralized Interface VPC endpoints for. Service names are built as com.amazonaws.<region>.<service>. | `list(string)` | <pre>[<br/>  "ec2",<br/>  "ssm",<br/>  "ssmmessages",<br/>  "ec2messages",<br/>  "kms",<br/>  "logs",<br/>  "sts"<br/>]</pre> | no |
| <a name="input_private_hosted_zone_name"></a> [private\_hosted\_zone\_name](#input\_private\_hosted\_zone\_name) | Name of the shared Route 53 private hosted zone for split-horizon DNS. Empty string skips creating the zone. | `string` | `""` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs to associate with the interface endpoint ENIs. Empty (default) = a module-owned group that admits HTTPS from allowed\_cidrs (when allowed\_cidrs is set). | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs (one per AZ, in the hub VPC) to place the interface endpoint ENIs in. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_endpoint_ids"></a> [endpoint\_ids](#output\_endpoint\_ids) | Map of interface service name to the created VPC endpoint ID. |
| <a name="output_phz_id"></a> [phz\_id](#output\_phz\_id) | Zone ID of the shared private hosted zone, or null when no zone was created. |
| <a name="output_shared_dns_zone_arns"></a> [shared\_dns\_zone\_arns](#output\_shared\_dns\_zone\_arns) | Map of interface service to the ARN of its private hosted zone (enable\_shared\_private\_dns), empty otherwise. Add these to a Route 53 Profile so spoke VPCs resolve the central endpoints. |
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
