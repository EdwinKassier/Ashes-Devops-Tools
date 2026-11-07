# aws/security/config-recorder-stackset

Org-wide AWS Config recorders deployed through one service-managed StackSet,
owned by the aws-organization stage.

- Every account under `target_ou_ids` gets a customer recorder and delivery
  channel in every enabled Region, **except the security-tooling account**
  (`account_filter_type = "DIFFERENCE"`), which keeps its own aggregator
  recorder. Auto-deployment covers accounts that join a target OU later.
- Service-managed StackSets never deploy to the management account. The
  aws-organization stage gives it a direct recorder instead.
- The template is built with `jsonencode()` and creates **no IAM resources**.
  The recorder uses the account's Config service-linked role
  (`AWSServiceRoleForConfig`) at its fixed ARN.
- Global resource types are recorded only in `home_region`.
- Delivery goes to the log-archive bucket (`aws.log_archive_bucket_name`).

> **Changing `deployment_targets` forces replacement.** Editing `target_ou_ids`
> or `security_tooling_account_id` replaces every stack instance, so every
> recorder is deleted and recreated (a short recording gap).

CloudFormation cannot adopt an existing recorder, and an account holds one
customer recorder per Region. Accounts that still have a Terraform-managed
recorder fail their stack instance until it is deleted. Follow
[`docs/runbooks/aws-config-recorder-migration.md`](../../../../docs/runbooks/aws-config-recorder-migration.md);
`migration_failure_tolerance_percentage = 100` lets that pass apply.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	log_archive_bucket_name =
	security_tooling_account_id =
	target_ou_ids =
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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_cloudformation_stack_set.this (modules/aws/security/config-recorder-stackset/main.tf#L65)
- resource.aws_cloudformation_stack_set_instance.this (modules/aws/security/config-recorder-stackset/main.tf#L99)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket the delivery channels write to (aws.log\_archive\_bucket\_name). Its bucket policy, owned by aws-security, must allow AWS Config delivery from the organization. | `string` | n/a | yes |
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit ID of the security-tooling account, excluded from the StackSet (DIFFERENCE filter): it keeps its own aggregator recorder. Changing it forces replacement of the stack instances. | `string` | n/a | yes |
| <a name="input_target_ou_ids"></a> [target\_ou\_ids](#input\_target\_ou\_ids) | OU IDs (or the organization root ID) whose accounts get the recorder. Every account under them except security\_tooling\_account\_id is targeted, and accounts that later join them are auto-deployed. Changing this list forces replacement of the stack instances. | `list(string)` | n/a | yes |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions that get a recorder (one stack instance set per Region). | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_call_as"></a> [call\_as](#input\_call\_as) | Manage the StackSet as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED\_ADMIN). | `string` | `"SELF"` | no |
| <a name="input_delivery_channel_name"></a> [delivery\_channel\_name](#input\_delivery\_channel\_name) | Name of the delivery channel in each account and Region. | `string` | `"org-delivery"` | no |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | The only Region whose recorder records global resource types (IAM), so global items are not duplicated per Region. Must be one of aws\_enabled\_regions. | `string` | `"eu-west-2"` | no |
| <a name="input_max_concurrent_percentage"></a> [max\_concurrent\_percentage](#input\_max\_concurrent\_percentage) | Maximum percentage of accounts per Region a stack operation runs in at once. | `number` | `25` | no |
| <a name="input_migration_failure_tolerance_percentage"></a> [migration\_failure\_tolerance\_percentage](#input\_migration\_failure\_tolerance\_percentage) | Percentage of accounts per Region in which a stack operation may fail without failing the whole operation (operation\_preferences.failure\_tolerance\_percentage). 0 (default) for routine runs; the migration pass sets 100 while legacy recorders still block some accounts, then returns to 0. | `number` | `0` | no |
| <a name="input_recorder_name"></a> [recorder\_name](#input\_recorder\_name) | Name of the configuration recorder in each account and Region. | `string` | `"org-recorder"` | no |
| <a name="input_stack_set_name"></a> [stack\_set\_name](#input\_stack\_set\_name) | Name of the recorder StackSet. | `string` | `"org-config-recorders"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the StackSet. Org-wide tags come from the root provider's default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_failure_tolerance_percentage"></a> [failure\_tolerance\_percentage](#output\_failure\_tolerance\_percentage) | The failure tolerance the stack instance operations run with (0 routine, 100 during the migration pass). |
| <a name="output_stack_set_id"></a> [stack\_set\_id](#output\_stack\_set\_id) | ID of the recorder StackSet. |
| <a name="output_stack_set_instances"></a> [stack\_set\_instances](#output\_stack\_set\_instances) | Per-Region stack instance deployment targets: target OUs, the account filter and the excluded account. |
| <a name="output_stack_set_name"></a> [stack\_set\_name](#output\_stack\_set\_name) | Name of the recorder StackSet. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "org_config_recorders" {
  source = "../../security/config-recorder-stackset"

  target_ou_ids               = [module.organization.roots_id]
  security_tooling_account_id = module.account["security_tooling"].account_id
  aws_enabled_regions         = ["eu-west-2", "eu-west-1"]
  home_region                 = "eu-west-2"
  log_archive_bucket_name     = "acme-org-log-archive"
}
```
