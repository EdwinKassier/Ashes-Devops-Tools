# systems-manager

AWS Systems Manager operational baseline for the SRA landing zone. Manages a
KMS-encrypted Session Manager preferences document (dual S3 + CloudWatch
logging), an auto-approving patch baseline set as the account/OS default, and a
software-inventory State Manager association across all managed instances.

## Per-account association (Convention 9)

SSM is an account-scoped, not organization-scoped, capability. This module is
instantiated **per account**: the organization/home account wires it through
the workload **stage**, and each workload account wires it through
**aws-workload**. There is no single org-wide SSM resource — the baseline,
default-baseline binding, and inventory association are created inside every
account that runs the stage.

## Quick Setup / patch policies (console-driven note)

AWS Systems Manager **Quick Setup patch policies** are deployed as
CloudFormation StackSets and remain partly console-driven; they are not managed
here. This module manages the patch **baseline** and its account default
binding only. Layer Quick Setup patch policies (scan/install scheduling, patch
groups) on top via the console or a dedicated StackSet if you need scheduled
remediation beyond baseline approval.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	kms_key_id = 
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


- resource.aws_ssm_association.inventory (modules/aws/systems-manager/main.tf#L68)
- resource.aws_ssm_default_patch_baseline.this (modules/aws/systems-manager/main.tf#L62)
- resource.aws_ssm_document.session_preferences (modules/aws/systems-manager/main.tf#L19)
- resource.aws_ssm_patch_baseline.this (modules/aws/systems-manager/main.tf#L39)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ID or ARN used to encrypt Session Manager sessions and logs. | `string` | n/a | yes |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | Name of the S3 bucket that receives Session Manager session logs. | `string` | n/a | yes |
| <a name="input_cloudwatch_log_group"></a> [cloudwatch\_log\_group](#input\_cloudwatch\_log\_group) | CloudWatch Logs log group name that receives Session Manager session logs. | `string` | `"/aws/ssm/session-logs"` | no |
| <a name="input_inventory_association_name"></a> [inventory\_association\_name](#input\_inventory\_association\_name) | Name of the software-inventory State Manager association. | `string` | `"org-inventory"` | no |
| <a name="input_inventory_schedule"></a> [inventory\_schedule](#input\_inventory\_schedule) | Schedule expression (rate or cron) for the software-inventory association. | `string` | `"rate(1 day)"` | no |
| <a name="input_patch_approve_after_days"></a> [patch\_approve\_after\_days](#input\_patch\_approve\_after\_days) | Number of days to wait after a patch is released before auto-approving it. | `number` | `7` | no |
| <a name="input_patch_baseline_name"></a> [patch\_baseline\_name](#input\_patch\_baseline\_name) | Name of the SSM patch baseline. | `string` | `"org-patch-baseline"` | no |
| <a name="input_patch_operating_system"></a> [patch\_operating\_system](#input\_patch\_operating\_system) | Operating system the patch baseline targets. Also used to set the account default patch baseline for that OS. | `string` | `"AMAZON_LINUX_2"` | no |
| <a name="input_session_document_name"></a> [session\_document\_name](#input\_session\_document\_name) | Name of the custom Session Manager preferences document. A custom name (not the reserved SSM-SessionManagerRunShell) keeps preferences under Terraform control per account. | `string` | `"SessionManagerPreferences"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_patch_baseline_id"></a> [patch\_baseline\_id](#output\_patch\_baseline\_id) | ID of the SSM patch baseline created by this module. |
| <a name="output_session_document_name"></a> [session\_document\_name](#output\_session\_document\_name) | Name of the Session Manager preferences document. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "systems_manager" {
  source = "../../modules/aws/systems-manager"

  log_bucket_name = "org-ssm-session-logs"
  kms_key_id      = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"

  # Patch and inventory defaults (AMAZON_LINUX_2, 7-day approval, daily
  # inventory) are usually fine; override per account as needed.
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
