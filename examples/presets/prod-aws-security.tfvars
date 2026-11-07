# Production hardening overlay for envs/aws/security. Merge its keys into your own tfvars.
#
# CloudTrail -> CloudWatch Logs + the full CIS AWS section-4 metric-filter alarm set
# (4.1-4.15). These are now the defaults (a dedicated logs-granted CMK and a
# KMS-encrypted SNS topic are created in the management account); pinned here so a
# cost preset cannot silently weaken production. Optionally bring your own CMK:
#
# Every key below sits in the root's aws_overrides object. A tfvars file sets
# the WHOLE object, so a second -var-file replaces (does not merge with) your own
# aws_overrides: copy these keys into your own aws_overrides instead.
aws_overrides = {
  enable_cloudwatch_logs = true
  # cloudwatch_logs_kms_key_arn = "arn:aws:kms:<region>:<management-account-id>:key/<key-id>"
  # cloudtrail_alarm_subscribers = { secops = { protocol = "email", endpoint = "secops@example.com" } }

  # CloudTrail S3 object-level data events. "write" = CIS 3.8 (default); "all" adds
  # CIS 3.9 read events. COST: billed per event org-wide — "all" on busy data-lake
  # buckets can be expensive; exclude them with cloudtrail_s3_data_events_excluded_bucket_arns.
  cloudtrail_s3_data_events = "all"

  # Full-coverage detection (these are the defaults; pinned here so a cost preset or a
  # workspace variable cannot silently weaken production).
  config_record_all_supported             = true
  guardduty_enable_ebs_malware_protection = true
  enabled_security_services               = ["macie", "inspector"]
}
