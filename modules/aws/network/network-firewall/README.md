# network-firewall

Gated AWS Network Firewall for the SRA landing zone inspection VPC. The firewall
policy forwards all stateless traffic (including fragments) to the stateful
engine (`aws:forward_to_sfe`), which runs in **STRICT_ORDER**:

| Priority | Rule group | Default |
|---|---|---|
| 100+ | AWS-managed threat groups (`managed_rule_groups`), attached by ARN `arn:aws:network-firewall:<region>:aws-managed:stateful-rulegroup/<name>` | `AttackInfrastructureStrictOrder`, `MalwareDomainsStrictOrder`, `BotNetCommandAndControlDomainsStrictOrder` |
| 1000 | Custom Suricata rules (`suricata_rules`) | none |
| 2000 | Egress domain allowlist on `HTTP_HOST` + `TLS_SNI` (`egress_domain_allowlist`) | none |
| default | `stateful_default_actions` for unmatched traffic | `["aws:alert_established"]` |

**Day-one safety.** The default action logs unmatched traffic but lets it pass,
so enabling the firewall never blackholes running workloads. Once allow rules or
the allowlist cover legitimate egress, switch to the AWS-recommended
`["aws:drop_established", "aws:alert_established"]`. A non-empty allowlist
drops all other HTTP/TLS from `HOME_NET`; set `home_net_cidrs` to the spoke
CIDRs (the network-hub stage passes `top_cidr`).

**Cost.** Managed rule groups consume policy capacity. Active threat defense
(`AttackInfrastructure*`) may be billed in addition to the firewall itself.

**Logging.** ALERT and FLOW logs both go to `log_bucket_name` under
`<log_prefix>/alert` and `<log_prefix>/flow`. Delivery uses
`delivery.logs.amazonaws.com`. A cross-account log-archive bucket must grant
that principal in its bucket policy and on its CMK (see known-gaps A8).

The entire module is gated behind `var.enable_network_firewall` (a **cost
toggle** — a firewall endpoint bills per AZ-hour plus per-GB processed). When
disabled, `count = 0` on every resource and the outputs degrade to null.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	inspection_vpc_id =
	log_bucket_name =
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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_networkfirewall_firewall.this (modules/aws/network/network-firewall/main.tf#L171)
- resource.aws_networkfirewall_firewall_policy.this (modules/aws/network/network-firewall/main.tf#L123)
- resource.aws_networkfirewall_logging_configuration.this (modules/aws/network/network-firewall/main.tf#L199)
- resource.aws_networkfirewall_rule_group.domain_allowlist (modules/aws/network/network-firewall/main.tf#L90)
- resource.aws_networkfirewall_rule_group.stateful (modules/aws/network/network-firewall/main.tf#L63)
- data source.aws_region.current (modules/aws/network/network-firewall/main.tf#L37)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_inspection_vpc_id"></a> [inspection\_vpc\_id](#input\_inspection\_vpc\_id) | ID of the inspection VPC the firewall is deployed into. | `string` | n/a | yes |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | Name of the S3 bucket that receives firewall flow logs. | `string` | n/a | yes |
| <a name="input_delete_protection"></a> [delete\_protection](#input\_delete\_protection) | Whether to enable deletion protection on the firewall. On by default so the inspection firewall is not torn down accidentally; set false to allow teardown. | `bool` | `true` | no |
| <a name="input_domain_allowlist_capacity"></a> [domain\_allowlist\_capacity](#input\_domain\_allowlist\_capacity) | Reserved capacity for the egress domain allowlist rule group (roughly 2 x number of domains for HTTP\_HOST + TLS\_SNI). Cannot be changed after creation. | `number` | `200` | no |
| <a name="input_egress_domain_allowlist"></a> [egress\_domain\_allowlist](#input\_egress\_domain\_allowlist) | Optional egress domain allowlist matched on HTTP Host and TLS SNI (e.g. [".amazonaws.com", "github.com"]; a leading dot matches subdomains). When non-empty an ALLOWLIST rule group passes these domains and DROPS all other HTTP/TLS traffic from HOME\_NET — set home\_net\_cidrs to the spoke CIDRs first. Empty (default) = no domain filtering. | `list(string)` | `[]` | no |
| <a name="input_enable_network_firewall"></a> [enable\_network\_firewall](#input\_enable\_network\_firewall) | Whether to deploy the Network Firewall. COST TOGGLE: an AWS Network Firewall bills per endpoint-hour (one endpoint per firewall subnet) plus per-GB processed. Set false to remove all firewall resources. | `bool` | `true` | no |
| <a name="input_firewall_name"></a> [firewall\_name](#input\_firewall\_name) | Name of the firewall. | `string` | `"org-firewall"` | no |
| <a name="input_firewall_subnet_ids"></a> [firewall\_subnet\_ids](#input\_firewall\_subnet\_ids) | Subnet IDs (one per AZ, in the inspection VPC) the firewall creates endpoints in. One subnet\_mapping is created per ID. | `list(string)` | <pre>[<br/>  "subnet-aaaa",<br/>  "subnet-bbbb"<br/>]</pre> | no |
| <a name="input_home_net_cidrs"></a> [home\_net\_cidrs](#input\_home\_net\_cidrs) | CIDRs set as the policy-level HOME\_NET variable. In a centralized inspection VPC this MUST cover the spoke VPCs (e.g. the org supernet); empty (default) = AWS default (the inspection VPC CIDR only). | `list(string)` | `[]` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of a customer-managed KMS key used to encrypt the rule group, policy, and firewall at rest (CUSTOMER\_KMS). Empty string falls back to AWS-owned keys; the network-hub stage that owns the KMS key wires this in production. | `string` | `""` | no |
| <a name="input_log_prefix"></a> [log\_prefix](#input\_log\_prefix) | S3 key prefix for the firewall logs in log\_bucket\_name (ALERT logs under <prefix>/alert, FLOW logs under <prefix>/flow). | `string` | `"network-firewall"` | no |
| <a name="input_managed_rule_groups"></a> [managed\_rule\_groups](#input\_managed\_rule\_groups) | AWS-managed stateful rule group NAMES attached in order (priority 100, 101, ...) as arn:aws:network-firewall:<region>:aws-managed:stateful-rulegroup/<name>. Must be the StrictOrder variants. Defaults: active threat defense (AttackInfrastructure) plus the malware and botnet C2 domain lists. Other examples: ThreatSignaturesMalwareStrictOrder, ThreatSignaturesBotnetStrictOrder, AbusedLegitMalwareDomainsStrictOrder. Managed groups consume policy capacity; active threat defense may carry additional charges. | `list(string)` | <pre>[<br/>  "AttackInfrastructureStrictOrder",<br/>  "MalwareDomainsStrictOrder",<br/>  "BotNetCommandAndControlDomainsStrictOrder"<br/>]</pre> | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition used to build the AWS-managed rule group ARNs. | `string` | `"aws"` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Name of the firewall policy. | `string` | `"org-fw-policy"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region the firewall is deployed in, used to build the AWS-managed rule group ARNs. Null (default) = the provider's region. | `string` | `null` | no |
| <a name="input_rule_group_capacity"></a> [rule\_group\_capacity](#input\_rule\_group\_capacity) | Reserved capacity units for the custom Suricata rule group (only created when suricata\_rules is set). Must be sized for the expected number of rules and cannot be changed after creation. | `number` | `100` | no |
| <a name="input_rule_group_name"></a> [rule\_group\_name](#input\_rule\_group\_name) | Name of the custom Suricata rule group (the allowlist group is named <rule\_group\_name>-egress-allowlist). | `string` | `"org-stateful"` | no |
| <a name="input_stateful_default_actions"></a> [stateful\_default\_actions](#input\_stateful\_default\_actions) | STRICT\_ORDER default actions for traffic no rule matched. Default ["aws:alert\_established"] = log-but-pass (safe on day one: never blackholes existing flows). AWS-recommended steady state once allow rules exist: ["aws:drop\_established", "aws:alert\_established"]. At most one drop and one alert action. | `list(string)` | <pre>[<br/>  "aws:alert_established"<br/>]</pre> | no |
| <a name="input_suricata_rules"></a> [suricata\_rules](#input\_suricata\_rules) | Optional custom Suricata rules (evaluated at priority 1000, after the AWS-managed threat groups, under STRICT\_ORDER). Empty (default) = no custom rule group. Rules must not rely on action-order semantics. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_arn"></a> [firewall\_arn](#output\_firewall\_arn) | ARN of the Network Firewall, or null when the firewall is disabled. |
| <a name="output_firewall_endpoint_ids"></a> [firewall\_endpoint\_ids](#output\_firewall\_endpoint\_ids) | VPC endpoint IDs from the firewall's per-AZ sync states, or the firewall ID as a fallback (sync-state endpoint IDs are provider-computed and may be unknown at plan time). Null when disabled. |
| <a name="output_firewall_endpoint_ids_by_az"></a> [firewall\_endpoint\_ids\_by\_az](#output\_firewall\_endpoint\_ids\_by\_az) | Map of availability zone -> Network Firewall VPC endpoint ID, from the firewall's per-AZ sync states. Used to route each AZ's inspection traffic to the SAME-AZ endpoint (symmetric routing with TGW appliance mode). Empty when disabled; values are provider-computed (known after apply). |
| <a name="output_stateful_rule_group_references"></a> [stateful\_rule\_group\_references](#output\_stateful\_rule\_group\_references) | Ordered list of { arn, priority } stateful rule group references in the STRICT\_ORDER policy (managed threat groups, then custom rules, then the egress allowlist). |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "network_firewall" {
  source = "../../modules/aws/network-firewall"

  inspection_vpc_id = "vpc-0123456789abcdef0"
  log_bucket_name   = "my-firewall-log-bucket"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
