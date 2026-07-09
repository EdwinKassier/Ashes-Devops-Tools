# Basic working example for the aws/security-notifications module.
# Provisions the KMS-encrypted SNS topic, the detective EventBridge rules, one
# email subscriber, and the Security Hub automation rule.
# Run `terraform init && terraform validate` here.

module "security_notifications" {
  source = "../../"

  kms_key_id = "arn:aws:kms:eu-west-2:111111111111:key/abcd1234-abcd-1234-abcd-1234567890ab"

  notification_subscribers = {
    secops = { protocol = "email", endpoint = "secops@example.com" }
  }

  break_glass_role_arn = "arn:aws:iam::111111111111:role/break-glass"
}
