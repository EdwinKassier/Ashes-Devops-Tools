locals {
  # Local services that use the security-tooling CMK. events.amazonaws.com is
  # required because the security-notifications SNS topic is encrypted with this
  # key: without it, EventBridge cannot publish the sec-notify-* alerts to the
  # topic. The grant is scoped to this account (aws:SourceAccount).
  sectool_cmk_service_principals = [
    "sns.amazonaws.com",
    "ssm.amazonaws.com",
    "cloudwatch.amazonaws.com",
    "events.amazonaws.com",
  ]
}
