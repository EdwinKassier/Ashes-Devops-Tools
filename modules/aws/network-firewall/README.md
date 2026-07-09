# network-firewall

Gated AWS Network Firewall for the SRA landing zone inspection VPC. A STATEFUL
Suricata rule group is referenced by a firewall policy whose stateless defaults
forward all traffic (including fragments) to the stateful engine
(`aws:forward_to_sfe`); the firewall is deployed into the inspection VPC with one
subnet mapping per firewall subnet, and flow logs are delivered to S3.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_networkfirewall_firewall.this (modules/aws/network-firewall/main.tf#L72)
- resource.aws_networkfirewall_firewall_policy.this (modules/aws/network-firewall/main.tf#L46)
- resource.aws_networkfirewall_logging_configuration.this (modules/aws/network-firewall/main.tf#L99)
- resource.aws_networkfirewall_rule_group.stateful (modules/aws/network-firewall/main.tf#L23)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_inspection_vpc_id"></a> [inspection\_vpc\_id](#input\_inspection\_vpc\_id) | ID of the inspection VPC the firewall is deployed into. | `string` | n/a | yes |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | Name of the S3 bucket that receives firewall flow logs. | `string` | n/a | yes |
| <a name="input_delete_protection"></a> [delete\_protection](#input\_delete\_protection) | Whether to enable deletion protection on the firewall. On by default so the inspection firewall is not torn down accidentally; set false to allow teardown. | `bool` | `true` | no |
| <a name="input_enable_network_firewall"></a> [enable\_network\_firewall](#input\_enable\_network\_firewall) | Whether to deploy the Network Firewall. COST TOGGLE: an AWS Network Firewall bills per endpoint-hour (one endpoint per firewall subnet) plus per-GB processed. Set false to remove all firewall resources. | `bool` | `true` | no |
| <a name="input_firewall_name"></a> [firewall\_name](#input\_firewall\_name) | Name of the firewall. | `string` | `"org-firewall"` | no |
| <a name="input_firewall_subnet_ids"></a> [firewall\_subnet\_ids](#input\_firewall\_subnet\_ids) | Subnet IDs (one per AZ, in the inspection VPC) the firewall creates endpoints in. One subnet\_mapping is created per ID. | `list(string)` | <pre>[<br/>  "subnet-aaaa",<br/>  "subnet-bbbb"<br/>]</pre> | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of a customer-managed KMS key used to encrypt the rule group, policy, and firewall at rest (CUSTOMER\_KMS). Empty string falls back to AWS-owned keys; the network-hub stage that owns the KMS key wires this in production. | `string` | `""` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Name of the firewall policy. | `string` | `"org-fw-policy"` | no |
| <a name="input_rule_group_capacity"></a> [rule\_group\_capacity](#input\_rule\_group\_capacity) | Reserved capacity units for the stateful rule group. Must be sized for the expected number of rules and cannot be changed after creation. | `number` | `100` | no |
| <a name="input_rule_group_name"></a> [rule\_group\_name](#input\_rule\_group\_name) | Name of the stateful rule group. | `string` | `"org-stateful"` | no |
| <a name="input_suricata_rules"></a> [suricata\_rules](#input\_suricata\_rules) | Suricata rules string for the stateful rule group. Defaults to a minimal drop rule; replace with the org rule set or AWS-managed rule references in production. | `string` | `"drop http any any -> any any (msg:\"deny by default\"; sid:1; rev:1;)"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_arn"></a> [firewall\_arn](#output\_firewall\_arn) | ARN of the Network Firewall, or null when the firewall is disabled. |
| <a name="output_firewall_endpoint_ids"></a> [firewall\_endpoint\_ids](#output\_firewall\_endpoint\_ids) | VPC endpoint IDs from the firewall's per-AZ sync states, or the firewall ID as a fallback (sync-state endpoint IDs are provider-computed and may be unknown at plan time). Null when disabled. |
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
