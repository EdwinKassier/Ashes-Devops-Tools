# aws-workload stage

Phase-3 orchestration wrapper that builds everything a **single workload
account** needs to join the landing zone. It runs entirely in **one workload
account**, with a **default `aws` provider** (the workload's home region) plus a
**`us_east_1` alias** (same account) that the optional edge-security module needs
for CloudFront/WAF.

> **No SaaS here.** Supabase/Vercel workloads live only in `envs/saas` (Epic I).
> This stage is AWS-native infrastructure only — do not add SaaS composition.

Composed children:

- **vpc** (`vpc`) — a spoke VPC with `private` / `isolated` / `tgw` tiers. The
  CIDR is either the literal `vpc_cidr` or allocated from the shared IPAM pool
  (`ipam_pool_id`, the network account's regional pool shared over RAM). Gateway
  endpoints for `s3` + `dynamodb` keep that traffic off the transit gateway.
- **spoke TGW attachment** (`aws_ec2_transit_gateway_vpc_attachment`) — attaches
  the spoke VPC's `tgw`-tier subnets to the **shared** transit gateway
  (`tgw_id`), which the network account shared into this account over RAM. The
  attachment resource is created here (in the workload account, where the VPC
  lives), but route-table **association and propagation are managed by the
  network account** on the segmented hub, so both `transit_gateway_default_route_table_*`
  flags are `false`.
- **iam_role** (`iam-role`) — workload / cross-account roles. Break-glass is
  **off** (`enable_break_glass = false`): emergency access is an org-level
  construct owned by the security/management layer, not replicated per workload.
- **account_baseline** (`account-baseline`) — per-account guardrails: default EBS
  encryption per enabled region and the IAM password policy (defaults).
- **config_recorder** (`config-org`, `recorder_only = true`) — the **workload
  half** of the org Config topology. The **same** `config-org` module the home
  account's config stage uses, in recorder-only mode: a per-Region recorder +
  delivery channel + recorder status only. The org aggregator and conformance
  packs are skipped (they belong to the home account), so `aggregator_role_arn`
  is unused and left empty.
- **systems_manager** (`systems-manager`, optional, `enable_ssm` default `true`)
  — Session Manager preferences, patch baseline, software inventory. Requires a
  non-empty `kms_key_arn`.
- **edge_security** (`edge-security`, optional, `enable_edge` default `false`) —
  per-workload CloudFront + WAF edge. Its CloudFront/WAF/ACM resources use the
  `aws.us_east_1` alias.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	config_role_arn = 
	flow_log_destination_arn = 
	log_archive_bucket_name = 
	tgw_id = 
	
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


- account_baseline - ../../aws/account-baseline
- config_recorder - ../../aws/config-org
- edge_security - ../../aws/edge-security
- iam_role - ../../aws/iam-role
- systems_manager - ../../aws/systems-manager
- vpc - ../../aws/vpc


## Resources

The following resources are created:


- resource.aws_ec2_transit_gateway_vpc_attachment.spoke (modules/stages/aws-workload/main.tf#L66)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_config_role_arn"></a> [config\_role\_arn](#input\_config\_role\_arn) | ARN of the IAM role AWS Config assumes to record resource configurations in this account/Region. | `string` | n/a | yes |
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | ARN of the central log-archive S3 bucket that receives the spoke VPC's flow logs. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket that receives Config snapshots/history and Session Manager session logs. | `string` | n/a | yes |
| <a name="input_tgw_id"></a> [tgw\_id](#input\_tgw\_id) | ID of the SHARED transit gateway (shared into this workload account over RAM by the network account) that the spoke VPC attaches to. | `string` | n/a | yes |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to spread each subnet tier across. Only the first az\_count entries are used. | `list(string)` | <pre>[<br/>  "eu-west-2a",<br/>  "eu-west-2b"<br/>]</pre> | no |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which to enforce the account baseline (default EBS encryption) and deploy a Config recorder. Defaults to the single home Region. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the workload's spoke VPC is deployed in and the region the default provider operates in. Used for subnet math and gateway-endpoint service names. | `string` | `"eu-west-2"` | no |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Number of availability zones to spread each subnet tier across. | `number` | `2` | no |
| <a name="input_edge_name_prefix"></a> [edge\_name\_prefix](#input\_edge\_name\_prefix) | Prefix applied to the edge WAF Web ACL, CloudFront Shield protection, and metric names. Ignored when enable\_edge is false. | `string` | `"workload-edge"` | no |
| <a name="input_edge_origin_domain_name"></a> [edge\_origin\_domain\_name](#input\_edge\_origin\_domain\_name) | DNS name of the origin the edge CloudFront distribution fetches from. Ignored when enable\_edge is false. | `string` | `"origin.example.com"` | no |
| <a name="input_enable_edge"></a> [enable\_edge](#input\_enable\_edge) | Deploy the per-workload edge-security stack (CloudFront + WAF, in us-east-1). Off by default; a workload opts in when it fronts an internet-facing app. | `bool` | `false` | no |
| <a name="input_enable_ssm"></a> [enable\_ssm](#input\_enable\_ssm) | Deploy the Systems Manager baseline (Session Manager preferences, patch baseline, inventory). On by default. Requires a non-empty kms\_key\_arn (Session Manager sessions/logs are KMS-encrypted; an empty key would leave the session document's kmsKeyId blank). | `bool` | `true` | no |
| <a name="input_ipam_pool_id"></a> [ipam\_pool\_id](#input\_ipam\_pool\_id) | IPAM pool ID to allocate the spoke VPC CIDR from (the network account's regional pool, shared over RAM). Empty string uses the literal vpc\_cidr instead. | `string` | `""` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the CMK used as the account default EBS encryption key and (when enable\_ssm is true) to encrypt Session Manager sessions/logs. Empty string leaves default EBS encryption on the AWS-managed key; must be a non-empty key when enable\_ssm is true. | `string` | `""` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Spoke subnet tiers, keyed by tier name. newbits/number\_offset drive cidrsubnet(vpc\_cidr, newbits, number\_offset + az\_index); the tgw tier holds the transit-gateway attachment ENIs. Offsets are multiples of 8 (> az\_count) so per-AZ subnets never collide. | <pre>map(object({<br/>    newbits       = number<br/>    number_offset = number<br/>    public        = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "isolated": {<br/>    "newbits": 8,<br/>    "number_offset": 8<br/>  },<br/>  "private": {<br/>    "newbits": 8,<br/>    "number_offset": 0<br/>  },<br/>  "tgw": {<br/>    "newbits": 8,<br/>    "number_offset": 16<br/>  }<br/>}</pre> | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR of the workload spoke VPC. Used for subnet math; also the literal VPC CIDR when ipam\_pool\_id is empty. | `string` | `"10.20.0.0/16"` | no |
| <a name="input_workload_roles"></a> [workload\_roles](#input\_workload\_roles) | Map of workload / cross-account IAM role name to its configuration (trust\_policy JSON, managed\_policy\_arns, inline\_policy, etc.). Empty by default. | <pre>map(object({<br/>    trust_policy         = string<br/>    max_session_duration = optional(number, 3600)<br/>    managed_policy_arns  = optional(list(string), [])<br/>    inline_policy        = optional(string, "")<br/>    permissions_boundary = optional(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_subnet_ids_by_tier"></a> [subnet\_ids\_by\_tier](#output\_subnet\_ids\_by\_tier) | Map of subnet tier name to the list of subnet IDs created for that tier (one per AZ) in the spoke VPC. |
| <a name="output_tgw_attachment_id"></a> [tgw\_attachment\_id](#output\_tgw\_attachment\_id) | The ID of the spoke VPC's transit-gateway attachment to the shared hub. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the workload spoke VPC. |
| <a name="output_workload_role_arns"></a> [workload\_role\_arns](#output\_workload\_role\_arns) | Map of workload IAM role name to role ARN. |
<!-- END_TF_DOCS -->
