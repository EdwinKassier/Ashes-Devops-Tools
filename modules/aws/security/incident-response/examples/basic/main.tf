# Basic working example for the aws/incident-response module.
# Enables the GuardDuty-triggered isolation Lambda and the forensics role.
# Run `terraform init && terraform validate` here.

module "incident_response" {
  source = "../../"

  forensics_account_id = "333333333333"
  org_id               = "o-abc123def0"
}
