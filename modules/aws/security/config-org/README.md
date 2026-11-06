# config-org

AWS Config for the SRA landing zone: multi-Region configuration
recorders/delivery-channels/statuses plus, unless `recorder_only` is set, the
organization aggregator and optional organization conformance packs.

The C16 aws-config **stage** invokes this module with `recorder_only = false`
(home-account recorders across every enabled Region **plus** the org
aggregator). The aws-workload stage invokes it with `recorder_only = true` to
deploy just that workload account's per-Region recorder. Recorders for
brand-new accounts otherwise come from an out-of-band Config StackSet.

`include_global_resource_types` is only sent when `all_supported = true`
(`record_all_supported`), because the provider only accepts it in that mode.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	log_archive_bucket =
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


- resource.aws_config_configuration_aggregator.org (modules/aws/security/config-org/main.tf#L112)
- resource.aws_config_configuration_recorder.this (modules/aws/security/config-org/main.tf#L66)
- resource.aws_config_configuration_recorder_status.this (modules/aws/security/config-org/main.tf#L101)
- resource.aws_config_delivery_channel.this (modules/aws/security/config-org/main.tf#L92)
- resource.aws_config_organization_conformance_pack.this (modules/aws/security/config-org/main.tf#L126)
- resource.aws_iam_role.aggregator (modules/aws/security/config-org/main.tf#L47)
- resource.aws_iam_role_policy_attachment.aggregator (modules/aws/security/config-org/main.tf#L60)
- resource.aws_iam_service_linked_role.config (modules/aws/security/config-org/main.tf#L40)
- data source.aws_caller_identity.current (modules/aws/security/config-org/main.tf#L33)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_log_archive_bucket"></a> [log\_archive\_bucket](#input\_log\_archive\_bucket) | Name of the central log-archive S3 bucket that receives Config configuration snapshots and history. | `string` | n/a | yes |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | 12-digit ID of the account the recorders run in, used to build the service-linked-role ARN when config\_role\_arn = null. Null = read from aws\_caller\_identity. | `string` | `null` | no |
| <a name="input_aggregator_name"></a> [aggregator\_name](#input\_aggregator\_name) | Name of the organization configuration aggregator. Ignored when recorder\_only = true. | `string` | `"org-aggregator"` | no |
| <a name="input_aggregator_role_arn"></a> [aggregator\_role\_arn](#input\_aggregator\_role\_arn) | ARN of an existing IAM role the organization aggregator assumes to collect Config data across the organization. Null or "" (default) creates one here (aggregator\_role\_name, trusting config.amazonaws.com, with the AWS managed policy AWSConfigRoleForOrganizations) unless recorder\_only = true, where no aggregator exists. | `string` | `null` | no |
| <a name="input_aggregator_role_name"></a> [aggregator\_role\_name](#input\_aggregator\_role\_name) | Name of the aggregator IAM role created when aggregator\_role\_arn is null/empty and recorder\_only = false. | `string` | `"aws-config-org-aggregator"` | no |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which to deploy a Config recorder, delivery channel, and recorder status. One set of per-Region resources is created for each entry. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_config_role_arn"></a> [config\_role\_arn](#input\_config\_role\_arn) | ARN of the IAM role Config assumes to record resource configurations in each account/Region. Null (default) uses the account's AWS Config service-linked role AWSServiceRoleForConfig (AWS-recommended), created here when create\_service\_linked\_role = true. | `string` | `null` | no |
| <a name="input_conformance_packs"></a> [conformance\_packs](#input\_conformance\_packs) | Opt-in bring-your-own-pack hook: map of organization conformance packs to deploy (e.g. a NIST 800-53 sample YAML), keyed by pack name. Provide exactly one of template\_body or template\_s3\_uri per pack. No packs are bundled with this module. Ignored when recorder\_only = true. | <pre>map(object({<br/>    template_body   = optional(string)<br/>    template_s3_uri = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_create_service_linked_role"></a> [create\_service\_linked\_role](#input\_create\_service\_linked\_role) | With config\_role\_arn = null, create the AWSServiceRoleForConfig service-linked role (aws\_iam\_service\_linked\_role). Default true for freshly vended accounts; set false when the account already has it (Config was enabled before, e.g. by Control Tower or the console) — the recorder then references the existing role by its well-known ARN. Ignored when config\_role\_arn is set. | `bool` | `true` | no |
| <a name="input_delivery_channel_name"></a> [delivery\_channel\_name](#input\_delivery\_channel\_name) | Name applied to every per-Region delivery channel. | `string` | `"org-delivery"` | no |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | Home (aggregation) Region. Global resource types (IAM, etc.) are recorded ONLY by the recorder in this Region to avoid duplicating global configuration items in every Region. Must be one of aws\_enabled\_regions for global types to be recorded at all. | `string` | `"eu-west-2"` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition used to build the managed-policy and pre-existing service-linked-role ARNs (aws, aws-us-gov, aws-cn). | `string` | `"aws"` | no |
| <a name="input_record_all_supported"></a> [record\_all\_supported](#input\_record\_all\_supported) | COST TOGGLE. When true (default), each recorder records ALL supported resource types (and, being all\_supported, global resource types too). Recording every resource type in every Region is the most expensive Config mode; set false to pair with a narrower recording\_group managed out-of-band when cost matters. | `bool` | `true` | no |
| <a name="input_recorder_name"></a> [recorder\_name](#input\_recorder\_name) | Name applied to every per-Region configuration recorder. | `string` | `"org-recorder"` | no |
| <a name="input_recorder_only"></a> [recorder\_only](#input\_recorder\_only) | When true, deploy only the per-Region recorder/delivery-channel/status and skip the org aggregator and conformance packs. The aws-workload stage sets this true to deploy a single workload account's recorder; the home-account aws-config stage leaves it false. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aggregator_arn"></a> [aggregator\_arn](#output\_aggregator\_arn) | ARN of the organization configuration aggregator, or null when recorder\_only = true. |
| <a name="output_aggregator_role_arn"></a> [aggregator\_role\_arn](#output\_aggregator\_role\_arn) | ARN of the role the organization aggregator assumes (created here when aggregator\_role\_arn was null/empty), or null when recorder\_only = true. |
| <a name="output_config_role_arn"></a> [config\_role\_arn](#output\_config\_role\_arn) | ARN of the IAM role the recorders use: the explicit config\_role\_arn or the AWSServiceRoleForConfig service-linked role. |
| <a name="output_recorder_names"></a> [recorder\_names](#output\_recorder\_names) | Map of Region to the configuration recorder name deployed in that Region. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "config_org" {
  source = "../../modules/aws/config-org"

  config_role_arn     = aws_iam_service_linked_role.config.arn
  aggregator_role_arn = aws_iam_role.config_aggregator.arn
  log_archive_bucket  = module.log_archive_bucket.bucket_name

  aws_enabled_regions = ["eu-west-2", "eu-west-1"]

  # Opt-in: bring your own organization conformance pack (nothing bundled).
  # Provide exactly one of template_body / template_s3_uri per pack.
  conformance_packs = {
    nist-800-53 = {
      template_s3_uri = "s3://ashes-org-conformance-packs/nist-800-53.yaml"
    }
  }
}
```

Workload-account mode (recorder only, no aggregator or packs):

```hcl
module "config_org" {
  source = "../../modules/aws/config-org"

  recorder_only      = true
  config_role_arn    = aws_iam_service_linked_role.config.arn
  log_archive_bucket = "ashes-org-log-archive"
}
```

## Cost

`record_all_supported` defaults to `true`, which records **all** supported
resource types (and global resource types) in **every** enabled Region. This is
the most expensive Config mode. Set it to `false` when cost matters and manage a
narrower `recording_group` out-of-band.

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
