# Basic working example for the aws/incident-response module.
# Enables the GuardDuty-triggered isolation Lambda and the forensics role, and
# lets the forensics role decrypt snapshots encrypted with the forensics CMK.
# (The aws-security stage creates that key in the same plan and so also sets
# enable_forensics_kms_grant = true.) Run `terraform init && terraform validate` here.

module "incident_response" {
  source = "../../"

  forensics_account_id = "333333333333"
  org_id               = "o-abc123def0"

  forensics_kms_key_arn = "arn:aws:kms:eu-west-2:333333333333:key/00000000-0000-0000-0000-000000000000"
}
