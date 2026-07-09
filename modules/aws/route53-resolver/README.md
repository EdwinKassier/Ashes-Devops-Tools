# route53-resolver

Centralized DNS for the SRA landing zone. Creates inbound and outbound Route 53
Resolver endpoints, forwards selected domains to on-prem/third-party resolvers
via FORWARD rules, and distributes the DNS posture org-wide with a Route 53
Profile (the 2024+ sharing mechanism) shared over RAM to the organization ARN.

DNS Firewall (a block list plus a BLOCK rule wired into a rule group, associated
with the VPC and configured to fail closed) is on by default. Resolver query
logging ships DNS queries to the central Log Archive by default. DNSSEC
validation is optional and off by default.

The inbound endpoint lets on-prem resolvers query private hosted zones; the
outbound endpoint carries the FORWARD rules for workloads. The endpoint
`ip_address` block requires a minimum of two subnets, so `subnet_ids` must hold
at least two entries.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_arn = 
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


- resource.aws_ram_principal_association.org (modules/aws/route53-resolver/main.tf#L97)
- resource.aws_ram_resource_association.profile (modules/aws/route53-resolver/main.tf#L92)
- resource.aws_ram_resource_share.profile (modules/aws/route53-resolver/main.tf#L87)
- resource.aws_route53_resolver_dnssec_config.this (modules/aws/route53-resolver/main.tf#L165)
- resource.aws_route53_resolver_endpoint.inbound (modules/aws/route53-resolver/main.tf#L15)
- resource.aws_route53_resolver_endpoint.outbound (modules/aws/route53-resolver/main.tf#L28)
- resource.aws_route53_resolver_firewall_config.this (modules/aws/route53-resolver/main.tf#L140)
- resource.aws_route53_resolver_firewall_domain_list.blocked (modules/aws/route53-resolver/main.tf#L107)
- resource.aws_route53_resolver_firewall_rule.block (modules/aws/route53-resolver/main.tf#L120)
- resource.aws_route53_resolver_firewall_rule_group.this (modules/aws/route53-resolver/main.tf#L114)
- resource.aws_route53_resolver_firewall_rule_group_association.this (modules/aws/route53-resolver/main.tf#L131)
- resource.aws_route53_resolver_query_log_config.this (modules/aws/route53-resolver/main.tf#L149)
- resource.aws_route53_resolver_query_log_config_association.this (modules/aws/route53-resolver/main.tf#L156)
- resource.aws_route53_resolver_rule.fwd (modules/aws/route53-resolver/main.tf#L45)
- resource.aws_route53_resolver_rule_association.fwd (modules/aws/route53-resolver/main.tf#L61)
- resource.aws_route53profiles_profile.this (modules/aws/route53-resolver/main.tf#L73)
- resource.aws_route53profiles_resource_association.vpc (modules/aws/route53-resolver/main.tf#L77)
- data source.aws_caller_identity.current (modules/aws/route53-resolver/main.tf#L85)
- data source.aws_region.current (modules/aws/route53-resolver/main.tf#L83)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | AWS Organizations ARN granted access to the RAM share carrying the Route 53 Profile (org-wide DNS distribution). | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC that resolver rules, DNS firewall, query logging, DNSSEC, and the Route 53 Profile are associated with. | `string` | n/a | yes |
| <a name="input_blocked_domains"></a> [blocked\_domains](#input\_blocked\_domains) | Domains added to the DNS Firewall block list. Only used when enable\_dns\_firewall is true. Use FQDNs with a trailing dot (e.g. malware.example.). | `list(string)` | <pre>[<br/>  "malware.example."<br/>]</pre> | no |
| <a name="input_enable_dns_firewall"></a> [enable\_dns\_firewall](#input\_enable\_dns\_firewall) | Whether to create the DNS Firewall block list, rule group, BLOCK rule, VPC association, and fail-closed firewall config. | `bool` | `true` | no |
| <a name="input_enable_dnssec"></a> [enable\_dnssec](#input\_enable\_dnssec) | Whether to enable DNSSEC validation for the VPC. | `bool` | `false` | no |
| <a name="input_enable_query_logging"></a> [enable\_query\_logging](#input\_enable\_query\_logging) | Whether to create the resolver query log config and associate it with the VPC, shipping DNS queries to the central Log Archive. | `bool` | `true` | no |
| <a name="input_forward_rules"></a> [forward\_rules](#input\_forward\_rules) | FORWARD resolver rules keyed by rule name. Each rule forwards domain\_name to target\_ips via the outbound endpoint and is associated with the VPC. | <pre>map(object({<br/>    domain_name = string<br/>    target_ips  = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the names of all resolver, profile, RAM, and DNS firewall resources. | `string` | `"org"` | no |
| <a name="input_query_log_destination_arn"></a> [query\_log\_destination\_arn](#input\_query\_log\_destination\_arn) | ARN of the destination (S3 bucket, CloudWatch log group, or Kinesis stream) that receives resolver query logs. Required when enable\_query\_logging is true. | `string` | `""` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs attached to the inbound and outbound resolver endpoints. At least one is required by the resolver endpoint resource. | `list(string)` | <pre>[<br/>  "sg-aaaaaaaaaaaaaaaaa"<br/>]</pre> | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs the inbound and outbound resolver endpoints place IPs in. At least two are required (one per AZ) because the endpoint ip\_address block enforces a minimum of two entries. | `list(string)` | <pre>[<br/>  "subnet-aaaa",<br/>  "subnet-bbbb"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_rule_group_id"></a> [firewall\_rule\_group\_id](#output\_firewall\_rule\_group\_id) | The ID of the DNS Firewall rule group, or null when DNS Firewall is disabled. |
| <a name="output_inbound_endpoint_id"></a> [inbound\_endpoint\_id](#output\_inbound\_endpoint\_id) | The ID of the inbound Route 53 Resolver endpoint. |
| <a name="output_outbound_endpoint_id"></a> [outbound\_endpoint\_id](#output\_outbound\_endpoint\_id) | The ID of the outbound Route 53 Resolver endpoint. |
| <a name="output_resolver_profile_id"></a> [resolver\_profile\_id](#output\_resolver\_profile\_id) | The ID of the Route 53 Profile shared org-wide over RAM. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "route53_resolver" {
  source = "../../modules/aws/route53-resolver"

  name_prefix               = "org"
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.subnet_ids_by_tier["private"]
  org_arn                   = data.aws_organizations_organization.this.arn
  query_log_destination_arn = module.log_archive_bucket.arn

  forward_rules = {
    corp = {
      domain_name = "corp.example.com"
      target_ips  = ["10.0.0.2", "10.0.1.2"]
    }
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
