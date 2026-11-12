# route53-resolver

Centralized DNS for the SRA landing zone. A Route 53 Profile (the 2024+ sharing
mechanism) is shared over RAM to the organization ARN and carries the DNS
configuration: the DNS Firewall rule group, the FORWARD rules and the private
hosted zones in `profile_hosted_zone_arns`. The Route 53 Profiles API accepts
only private hosted zones, DNS Firewall rule groups, Resolver rules and
interface VPC endpoints as profile resources. A VPC is not one: each VPC joins
the profile with an `aws_route53profiles_association` in its own account.

DNS Firewall (a block list plus a BLOCK rule wired into a rule group, associated
with the VPC and configured to fail closed) is on by default. Resolver query
logging ships DNS queries to the central Log Archive by default. DNSSEC
validation is optional and off by default.

The inbound and outbound Resolver endpoints are opt-in
(`enable_resolver_endpoints`, about USD 365 per month together). The inbound
endpoint lets on-premises resolvers query private hosted zones; the outbound
endpoint carries the FORWARD rules, so `forward_rules` need the endpoints. The
endpoint `ip_address` block requires a minimum of two subnets, so `subnet_ids`
must hold at least two entries when the endpoints are on. With
`security_group_ids` empty the module owns the endpoint security group: DNS
(TCP and UDP 53) in from `allowed_cidrs`, DNS out to the forward target IPs
only. The provider replaces an endpoint when its security groups change.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_ram_principal_association.org (modules/aws/network/route53-resolver/main.tf#L196)
- resource.aws_ram_resource_association.profile (modules/aws/network/route53-resolver/main.tf#L191)
- resource.aws_ram_resource_share.profile (modules/aws/network/route53-resolver/main.tf#L185)
- resource.aws_route53_resolver_dnssec_config.this (modules/aws/network/route53-resolver/main.tf#L268)
- resource.aws_route53_resolver_endpoint.inbound (modules/aws/network/route53-resolver/main.tf#L73)
- resource.aws_route53_resolver_endpoint.outbound (modules/aws/network/route53-resolver/main.tf#L90)
- resource.aws_route53_resolver_firewall_config.this (modules/aws/network/route53-resolver/main.tf#L242)
- resource.aws_route53_resolver_firewall_domain_list.blocked (modules/aws/network/route53-resolver/main.tf#L206)
- resource.aws_route53_resolver_firewall_rule.block (modules/aws/network/route53-resolver/main.tf#L221)
- resource.aws_route53_resolver_firewall_rule_group.this (modules/aws/network/route53-resolver/main.tf#L214)
- resource.aws_route53_resolver_firewall_rule_group_association.this (modules/aws/network/route53-resolver/main.tf#L232)
- resource.aws_route53_resolver_query_log_config.this (modules/aws/network/route53-resolver/main.tf#L251)
- resource.aws_route53_resolver_query_log_config_association.this (modules/aws/network/route53-resolver/main.tf#L259)
- resource.aws_route53_resolver_rule.fwd (modules/aws/network/route53-resolver/main.tf#L121)
- resource.aws_route53_resolver_rule_association.fwd (modules/aws/network/route53-resolver/main.tf#L139)
- resource.aws_route53profiles_profile.this (modules/aws/network/route53-resolver/main.tf#L151)
- resource.aws_route53profiles_resource_association.firewall (modules/aws/network/route53-resolver/main.tf#L160)
- resource.aws_route53profiles_resource_association.hosted_zones (modules/aws/network/route53-resolver/main.tf#L177)
- resource.aws_route53profiles_resource_association.rules (modules/aws/network/route53-resolver/main.tf#L169)
- resource.aws_security_group.resolver (modules/aws/network/route53-resolver/main.tf#L24)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | AWS Organizations ARN granted access to the RAM share carrying the Route 53 Profile (org-wide DNS distribution). | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC that hosts the resolver endpoints and that the resolver rules, DNS firewall, query logging and DNSSEC are associated with. Other VPCs get the same rules, firewall and zones by associating the shared Route 53 Profile. | `string` | n/a | yes |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDRs that may send DNS (TCP and UDP 53) to the inbound endpoint when the module owns the security group (for example the org supernet and the on-premises ranges). Required when enable\_resolver\_endpoints is true and security\_group\_ids is empty. | `list(string)` | `[]` | no |
| <a name="input_blocked_domains"></a> [blocked\_domains](#input\_blocked\_domains) | Domains added to the DNS Firewall block list. Only used when enable\_dns\_firewall is true. Use FQDNs with a trailing dot (e.g. malware.example.). | `list(string)` | <pre>[<br/>  "malware.example."<br/>]</pre> | no |
| <a name="input_enable_dns_firewall"></a> [enable\_dns\_firewall](#input\_enable\_dns\_firewall) | Whether to create the DNS Firewall block list, rule group, BLOCK rule, VPC association, and fail-closed firewall config. | `bool` | `true` | no |
| <a name="input_enable_dnssec"></a> [enable\_dnssec](#input\_enable\_dnssec) | Whether to enable DNSSEC validation for the VPC. | `bool` | `false` | no |
| <a name="input_enable_query_logging"></a> [enable\_query\_logging](#input\_enable\_query\_logging) | Whether to create the resolver query log config and associate it with the VPC, shipping DNS queries to the central Log Archive. | `bool` | `true` | no |
| <a name="input_enable_resolver_endpoints"></a> [enable\_resolver\_endpoints](#input\_enable\_resolver\_endpoints) | Create the inbound and outbound Resolver endpoints (2 ENIs each, about USD 365 per month together). Needed for on-premises resolution in either direction and for forward\_rules. Default false. | `bool` | `false` | no |
| <a name="input_forward_rules"></a> [forward\_rules](#input\_forward\_rules) | FORWARD resolver rules keyed by rule name. Each rule forwards domain\_name to target\_ips via the outbound endpoint, is associated with the VPC and is added to the Route 53 Profile. Needs enable\_resolver\_endpoints = true. | <pre>map(object({<br/>    domain_name = string<br/>    target_ips  = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the names of all resolver, profile, RAM, and DNS firewall resources. | `string` | `"org"` | no |
| <a name="input_profile_hosted_zone_arns"></a> [profile\_hosted\_zone\_arns](#input\_profile\_hosted\_zone\_arns) | Private hosted zones to add to the Route 53 Profile, keyed by a plan-known name. Every VPC that associates the profile resolves them. | `map(string)` | `{}` | no |
| <a name="input_query_log_destination_arn"></a> [query\_log\_destination\_arn](#input\_query\_log\_destination\_arn) | ARN of the destination (S3 bucket, CloudWatch log group, or Kinesis stream) that receives resolver query logs. Required when enable\_query\_logging is true. | `string` | `null` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security groups for the resolver endpoints. Empty (default) = a module-owned group that admits DNS (TCP and UDP 53) from allowed\_cidrs. The provider replaces an endpoint when its security groups change. | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs (one per AZ, at least two) for the endpoint IPs. Required when enable\_resolver\_endpoints is true. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_rule_group_id"></a> [firewall\_rule\_group\_id](#output\_firewall\_rule\_group\_id) | The ID of the DNS Firewall rule group, or null when DNS Firewall is disabled. |
| <a name="output_inbound_endpoint_id"></a> [inbound\_endpoint\_id](#output\_inbound\_endpoint\_id) | The ID of the inbound Route 53 Resolver endpoint, or null when enable\_resolver\_endpoints is false. |
| <a name="output_inbound_endpoint_ips"></a> [inbound\_endpoint\_ips](#output\_inbound\_endpoint\_ips) | IP addresses of the inbound Route 53 Resolver endpoint (the targets for on-premises conditional forwarders), or an empty list when enable\_resolver\_endpoints is false. |
| <a name="output_outbound_endpoint_id"></a> [outbound\_endpoint\_id](#output\_outbound\_endpoint\_id) | The ID of the outbound Route 53 Resolver endpoint, or null when enable\_resolver\_endpoints is false. |
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
