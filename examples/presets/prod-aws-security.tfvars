# Production hardening overlay for envs/aws/security. Apply IN ADDITION to your own tfvars.
#
# CloudTrail -> CloudWatch Logs + CIS control-plane metric-filter alarms.
# PREVIEW: mock-tested only. Supply a CMK whose key policy grants
# logs.<region>.amazonaws.com (otherwise the log group uses AWS-managed encryption):
enable_cloudwatch_logs = true
# cloudwatch_logs_kms_key_arn = "arn:aws:kms:<region>:<security-account-id>:key/<key-id>"

# Full-coverage detection (these are the defaults; pinned here so a cost preset or a
# workspace variable cannot silently weaken production).
config_record_all_supported             = true
guardduty_enable_ebs_malware_protection = true
enabled_security_services               = ["macie", "inspector"]
