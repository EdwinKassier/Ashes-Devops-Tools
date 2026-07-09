# securitylake

Amazon Security Lake — the Terraform-native **centralized OCSF security-data
lake** for the SRA landing zone. It runs in the delegated-administrator
(Security Tooling) account, normalizes AWS-native log sources into the Open
Cybersecurity Schema Framework (OCSF), and stores them in a service-managed S3
lake for centralized analytics.

Key points:

- The CloudWatch "Unified Data Store" concept has **no AWS resource** — Security
  Lake is the TF-native centralized-analytics layer, so it is what this module
  provisions.
- The S3 **Log Archive** bucket (see `modules/aws/log-archive-bucket`) remains
  the immutable, org-wide raw-log sink. Security Lake is the queryable,
  normalized analytics layer on top — the two are complementary, not
  substitutes.
- `enable_security_lake` is a **cost toggle**. Security Lake bills for
  ingestion, normalization, and storage, so it is gated independently of the
  rest of the security tooling and can be turned off wholesale.
- No cross-account provider is required: the delegated-admin account owns the
  data lake, the log-source subscriptions, and any subscribers.

The default log sources are `CLOUD_TRAIL_MGMT`, `VPC_FLOW`, `ROUTE53`, and
`SH_FINDINGS`. A subscriber is created only when `subscriber_principal` is set.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
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


- resource.aws_securitylake_aws_log_source.this (modules/aws/securitylake/main.tf#L25)
- resource.aws_securitylake_data_lake.this (modules/aws/securitylake/main.tf#L5)
- resource.aws_securitylake_subscriber.this (modules/aws/securitylake/main.tf#L36)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which Security Lake is enabled. One data-lake configuration block is created per Region. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_enable_security_lake"></a> [enable\_security\_lake](#input\_enable\_security\_lake) | Master COST toggle for Amazon Security Lake. When false the module creates no resources. Security Lake incurs ingestion, storage, and normalization charges, so it is gated separately from the rest of the security tooling. | `bool` | `true` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key identifier (key ID, ARN, or the literal S3\_MANAGED) used to encrypt the Security Lake S3 objects in each configured Region. | `string` | `"S3_MANAGED"` | no |
| <a name="input_log_sources"></a> [log\_sources](#input\_log\_sources) | AWS-native log sources ingested into Security Lake. Each must be one of CLOUD\_TRAIL\_MGMT, VPC\_FLOW, ROUTE53, or SH\_FINDINGS. | `list(string)` | <pre>[<br/>  "CLOUD_TRAIL_MGMT",<br/>  "VPC_FLOW",<br/>  "ROUTE53",<br/>  "SH_FINDINGS"<br/>]</pre> | no |
| <a name="input_meta_store_manager_role_arn"></a> [meta\_store\_manager\_role\_arn](#input\_meta\_store\_manager\_role\_arn) | ARN of the AmazonSecurityLakeMetaStoreManager IAM role used by Security Lake to manage the Lake Formation metastore. Required when enable\_security\_lake is true. | `string` | `""` | no |
| <a name="input_subscriber_external_id"></a> [subscriber\_external\_id](#input\_subscriber\_external\_id) | External ID used in the subscriber identity trust condition. | `string` | `"securitylake"` | no |
| <a name="input_subscriber_name"></a> [subscriber\_name](#input\_subscriber\_name) | Name of the optional Security Lake subscriber. Only used when subscriber\_principal is set. | `string` | `"security-tooling"` | no |
| <a name="input_subscriber_principal"></a> [subscriber\_principal](#input\_subscriber\_principal) | AWS account ID (12 digits) of the subscriber principal granted read access to the OCSF data. When empty, no subscriber is created. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_data_lake_arn"></a> [data\_lake\_arn](#output\_data\_lake\_arn) | ARN of the Security Lake data lake, or null when Security Lake is disabled. |
| <a name="output_log_source_names"></a> [log\_source\_names](#output\_log\_source\_names) | Names of the AWS-native log sources ingested into Security Lake. |
<!-- END_TF_DOCS -->
