# systems-manager

AWS Systems Manager operational baseline for the SRA landing zone. Manages a
KMS-encrypted Session Manager preferences document (dual S3 + CloudWatch
logging), one auto-approving patch baseline per operating system (each set as
the account default for its OS), Patch Manager scan and install associations,
and a software-inventory State Manager association across all managed
instances.

## Per-account association (Convention 9)

SSM is an account-scoped, not organization-scoped, capability. This module is
instantiated **per account**: the aws-security stage wires it into the
security-tooling account, and each workload account wires it through
**aws-workload**. There is no single org-wide SSM resource. The baselines,
default-baseline bindings and associations are created inside every account
(and only in the provider region) that runs the stage.

## Patching (scan and install)

Two `AWS-RunPatchBaseline` State Manager associations patch without a
maintenance window:

| Association | Operation | Schedule | Targets |
|:--|:--|:--|:--|
| `<patch_baseline_name>-scan` | `Scan` (reports compliance, no reboot) | `rate(1 day)` | every SSM-managed instance |
| `<patch_baseline_name>-install` | `Install`, `RebootOption = RebootIfNeeded` | `cron(0 3 ? * SUN *)` (Sunday 03:00 UTC), 10% concurrency, 10% error threshold | every SSM-managed instance, or only those with `patch_install_target_tag` |

- **Which instances it hits.** An SSM-managed instance is an EC2 instance (or
  hybrid node) that runs the SSM Agent and is registered with Systems Manager
  in this account and region: through an instance profile with
  `AmazonSSMManagedInstanceCore`, Default Host Management Configuration, or a
  hybrid activation. The landing zone itself launches no EC2 instances (its
  application runtime is ECS Fargate, and Patch Manager does not patch
  Fargate tasks), so by default the associations hit only the instances you
  run.
- **No reboot at apply time.** The install association sets
  `apply_only_at_cron_interval = true`. AWS otherwise runs a new association
  immediately; here the first install is the next cron time.
- **Opt out or narrow.** `enable_patch_install = false` keeps the scan only.
  `patch_install_target_tag = { key = "PatchInstall", value = "true" }` limits
  the install to the instances that carry that tag.
- **Operating systems.** `patch_operating_systems` (default
  `["AMAZON_LINUX_2023"]`) creates one custom baseline per OS. Amazon Linux 2
  reached end of support on 2026-06-30. Linux baselines approve `Security` and
  `Bugfix` updates of `Critical` or `Important` severity; the Windows baseline
  approves `CriticalUpdates` and `SecurityUpdates` of MSRC severity `Critical`
  or `Important`. For an OS that is not listed, Patch Manager uses the AWS
  predefined default baseline, and the install association still patches it.

## Quick Setup / patch policies (console-driven note)

AWS Systems Manager **Quick Setup patch policies** are deployed as
CloudFormation StackSets and remain partly console-driven; they are not managed
here. Use them only instead of the associations above, not in addition, or an
instance is patched twice.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_ssm_association.inventory (modules/aws/ops/systems-manager/main.tf#L170)
- resource.aws_ssm_association.patch_install (modules/aws/ops/systems-manager/main.tf#L145)
- resource.aws_ssm_association.patch_scan (modules/aws/ops/systems-manager/main.tf#L122)
- resource.aws_ssm_default_patch_baseline.this (modules/aws/ops/systems-manager/main.tf#L103)
- resource.aws_ssm_document.session_preferences (modules/aws/ops/systems-manager/main.tf#L26)
- resource.aws_ssm_patch_baseline.this (modules/aws/ops/systems-manager/main.tf#L74)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ID or ARN used to encrypt Session Manager sessions and logs. | `string` | n/a | yes |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | Name of the S3 bucket that receives Session Manager session logs. | `string` | n/a | yes |
| <a name="input_cloudwatch_log_group"></a> [cloudwatch\_log\_group](#input\_cloudwatch\_log\_group) | CloudWatch Logs log group name that receives Session Manager session logs. | `string` | `"/aws/ssm/session-logs"` | no |
| <a name="input_enable_patch_install"></a> [enable\_patch\_install](#input\_enable\_patch\_install) | Install approved patches on patch\_install\_schedule (AWS-RunPatchBaseline Operation=Install), on every SSM-managed instance in this account and region, or only on the instances that carry patch\_install\_target\_tag. Instances reboot when a patch needs it (patch\_reboot\_option). False keeps the daily scan only. | `bool` | `true` | no |
| <a name="input_inventory_association_name"></a> [inventory\_association\_name](#input\_inventory\_association\_name) | Name of the software-inventory State Manager association. | `string` | `"org-inventory"` | no |
| <a name="input_inventory_schedule"></a> [inventory\_schedule](#input\_inventory\_schedule) | Schedule expression (rate or cron) for the software-inventory association. | `string` | `"rate(1 day)"` | no |
| <a name="input_patch_approve_after_days"></a> [patch\_approve\_after\_days](#input\_patch\_approve\_after\_days) | Number of days to wait after a patch is released before auto-approving it. | `number` | `7` | no |
| <a name="input_patch_baseline_name"></a> [patch\_baseline\_name](#input\_patch\_baseline\_name) | Name of the SSM patch baseline. | `string` | `"org-patch-baseline"` | no |
| <a name="input_patch_install_schedule"></a> [patch\_install\_schedule](#input\_patch\_install\_schedule) | Cron expression (UTC) for the install association. The association runs only at this time, never at apply time (apply\_only\_at\_cron\_interval), so a rate() expression is rejected. Default: Sunday 03:00 UTC. | `string` | `"cron(0 3 ? * SUN *)"` | no |
| <a name="input_patch_install_target_tag"></a> [patch\_install\_target\_tag](#input\_patch\_install\_target\_tag) | Narrows the install association to the managed instances that carry this tag (key and value). Null (default) installs on every SSM-managed instance in this account and region. The daily scan always covers every managed instance. | <pre>object({<br/>    key   = string<br/>    value = string<br/>  })</pre> | `null` | no |
| <a name="input_patch_operating_system"></a> [patch\_operating\_system](#input\_patch\_operating\_system) | Single operating system for the patch baseline. Null (default) uses patch\_operating\_systems; a non-null value replaces that set with this one OS. | `string` | `null` | no |
| <a name="input_patch_operating_systems"></a> [patch\_operating\_systems](#input\_patch\_operating\_systems) | Operating systems that get a custom patch baseline, each set as the account default baseline for that OS. Supported: the Amazon Linux family, REDHAT\_ENTERPRISE\_LINUX, ROCKY\_LINUX, ALMA\_LINUX and WINDOWS. Amazon Linux 2 reached end of support on 2026-06-30: keep AMAZON\_LINUX\_2 here only while you still run it. Patch Manager uses the AWS predefined baseline for any OS not listed; the install association still patches those instances. | `set(string)` | <pre>[<br/>  "AMAZON_LINUX_2023"<br/>]</pre> | no |
| <a name="input_patch_reboot_option"></a> [patch\_reboot\_option](#input\_patch\_reboot\_option) | RebootIfNeeded (default) or NoReboot. NoReboot leaves instances in a pending-reboot state that Patch Manager reports as non-compliant. | `string` | `"RebootIfNeeded"` | no |
| <a name="input_session_document_name"></a> [session\_document\_name](#input\_session\_document\_name) | Name of the custom Session Manager preferences document. A custom name (not the reserved SSM-SessionManagerRunShell) keeps preferences under Terraform control per account. | `string` | `"SessionManagerPreferences"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_patch_baseline_id"></a> [patch\_baseline\_id](#output\_patch\_baseline\_id) | ID of the patch baseline for the first operating system in patch\_operating\_systems (sorted). Use patch\_baseline\_ids when the module manages more than one OS. |
| <a name="output_patch_baseline_ids"></a> [patch\_baseline\_ids](#output\_patch\_baseline\_ids) | Patch baseline ID per operating system. |
| <a name="output_patch_install_association_id"></a> [patch\_install\_association\_id](#output\_patch\_install\_association\_id) | ID of the weekly patch install association, or null when enable\_patch\_install is false. |
| <a name="output_patch_install_schedule"></a> [patch\_install\_schedule](#output\_patch\_install\_schedule) | Cron schedule of the weekly patch install association, or null when enable\_patch\_install is false. |
| <a name="output_patch_operating_systems"></a> [patch\_operating\_systems](#output\_patch\_operating\_systems) | Operating systems that have a custom default patch baseline in this account and region. |
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
