# security-notifications

Detective control for the SRA landing zone. Provisions a KMS-encrypted SNS
topic and a set of EventBridge rules that fan the key detective signals
(GuardDuty and Security Hub findings, root-account usage, console sign-in
without MFA, org-access-role and break-glass-role use) into that topic, plus a
Security Hub automation rule that auto-notes informational findings.

**A subscriber is required when the module is enabled.** Without at least one
entry in `notification_subscribers`, findings fire into a void — the variable
validation enforces this.

These are **detective** controls: they observe and alert, they do not block.
The preventive counterparts live elsewhere — the B3 SCP carve-out and the F1
disabled-by-default guardrail. The **break-glass** detective control lives here
(the iam-role module only defines the role); its alarm depends on the org
CloudTrail (C3) delivering STS events into the observed account.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	kms_key_id = 
	
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


- resource.aws_cloudwatch_event_rule.this (modules/aws/security-notifications/main.tf#L66)
- resource.aws_cloudwatch_event_target.this (modules/aws/security-notifications/main.tf#L72)
- resource.aws_securityhub_automation_rule.suppress_known (modules/aws/security-notifications/main.tf#L81)
- resource.aws_sns_topic.this (modules/aws/security-notifications/main.tf#L18)
- resource.aws_sns_topic_policy.this (modules/aws/security-notifications/main.tf#L25)
- resource.aws_sns_topic_subscription.this (modules/aws/security-notifications/main.tf#L43)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ID or ARN used to encrypt the SNS topic (kms\_master\_key\_id). | `string` | n/a | yes |
| <a name="input_automation_rule_name"></a> [automation\_rule\_name](#input\_automation\_rule\_name) | Name of the Security Hub automation rule that auto-notes informational findings. | `string` | `"sec-notify-suppress-informational"` | no |
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | ARN of the break-glass IAM role to watch for assumption. Any AssumeRole against this ARN raises a notification. The iam-role module defines the role; this module is its detective control. | `string` | `""` | no |
| <a name="input_enable_security_notifications"></a> [enable\_security\_notifications](#input\_enable\_security\_notifications) | Master switch for the security-notifications detective control. When false, no SNS topic, subscriptions, EventBridge rules, or Security Hub automation rule are created. | `bool` | `true` | no |
| <a name="input_notification_subscribers"></a> [notification\_subscribers](#input\_notification\_subscribers) | Map of subscribers to attach to the SNS topic, keyed by an arbitrary name. A subscriber is required when the module is enabled — otherwise findings fire into a void. | <pre>map(object({<br/>    protocol = string # "email" | "https" | "sms" | "sqs" | "lambda" | ...<br/>    endpoint = string # e.g. an email address or HTTPS URL<br/>  }))</pre> | `{}` | no |
| <a name="input_topic_name"></a> [topic\_name](#input\_topic\_name) | Name of the KMS-encrypted SNS topic that all security notifications are published to. | `string` | `"security-notifications"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_rule_names"></a> [rule\_names](#output\_rule\_names) | Names of the EventBridge rules that fan detective signals into the topic. |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | ARN of the security-notifications SNS topic, or null when disabled. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "security_notifications" {
  source = "../../modules/aws/security-notifications"

  kms_key_id = "arn:aws:kms:eu-west-2:111111111111:key/abcd1234-..."

  notification_subscribers = {
    secops = { protocol = "email", endpoint = "secops@example.com" }
  }

  # Optional: watch a break-glass role for assumption.
  break_glass_role_arn = "arn:aws:iam::111111111111:role/break-glass"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
