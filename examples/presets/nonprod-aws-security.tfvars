# Cost overlay for NON-PRODUCTION envs/aws/security (~USD 70-300/month saving).
# DO NOT use for production: drops Security Lake, Macie and Inspector, and reduces
# Config and GuardDuty coverage.
#
# Every key below sits in the root's aws_overrides object. A tfvars file sets
# the WHOLE object, so a second -var-file replaces (does not merge with) your own
# aws_overrides: copy these keys into your own aws_overrides instead.
aws_overrides = {
  enable_security_lake                    = false
  enabled_security_services               = []
  config_record_all_supported             = false
  guardduty_enable_ebs_malware_protection = false
}
