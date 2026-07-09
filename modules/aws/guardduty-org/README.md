# guardduty-org

Org-wide, multi-Region GuardDuty for the SRA landing zone.

The module spans two accounts via two providers:

- The **default** provider is the delegated-administrator account (Security
  Tooling). It owns the per-Region detector, the organization configuration
  (`auto_enable_organization_members = "ALL"`) and the protection-plan features.
- The aliased **`aws.management`** provider is the organization management
  account. It owns only the delegated-admin registration
  (`aws_guardduty_organization_admin_account`), which must be performed from the
  management account.

AWS provider v6 injects a per-resource `region`, so a single `aws.management`
alias covers every enabled Region through `region = each.value` — no per-Region
provider aliases are required.

Notes:

- **Extended Threat Detection** is enabled automatically once a detector exists;
  there is no separate Terraform resource for it.
- **S3 Malware Protection** (malware-protection-plan) is managed out-of-band and
  is intentionally not modelled here.
- The deprecated `datasources` block on the detector / organization
  configuration is intentionally omitted; data sources are configured through
  the `aws_guardduty_organization_configuration_feature` resources instead.
- `EBS_MALWARE_PROTECTION` is a documented **cost** toggle
  (`enable_ebs_malware_protection`) — agentless EBS malware scanning is billed
  per GB scanned.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	security_tooling_account_id = 
	
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
| <a name="provider_aws.management"></a> [aws.management](#provider\_aws.management) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_guardduty_detector.this (modules/aws/guardduty-org/main.tf#L25)
- resource.aws_guardduty_organization_admin_account.this (modules/aws/guardduty-org/main.tf#L33)
- resource.aws_guardduty_organization_configuration.this (modules/aws/guardduty-org/main.tf#L40)
- resource.aws_guardduty_organization_configuration_feature.this (modules/aws/guardduty-org/main.tf#L69)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling account nominated as the GuardDuty delegated administrator (the module's default provider). | `string` | n/a | yes |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which to enable org-wide GuardDuty. A detector, org configuration and protection-plan features are created in each. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_enable_ebs_malware_protection"></a> [enable\_ebs\_malware\_protection](#input\_enable\_ebs\_malware\_protection) | Enable the EBS\_MALWARE\_PROTECTION feature. COST toggle: agentless EBS malware scanning is billed per GB scanned, so it defaults on but can be disabled. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_detector_ids"></a> [detector\_ids](#output\_detector\_ids) | Map of Region to the GuardDuty detector ID created in that Region. |
<!-- END_TF_DOCS -->
