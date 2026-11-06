# Cost overlay for NON-PRODUCTION envs/aws/security (~USD 70-300/month saving).
# DO NOT use for production: drops Security Lake, Macie and Inspector, and reduces
# Config and GuardDuty coverage.
enable_security_lake                    = false
enabled_security_services               = []
config_record_all_supported             = false
guardduty_enable_ebs_malware_protection = false
