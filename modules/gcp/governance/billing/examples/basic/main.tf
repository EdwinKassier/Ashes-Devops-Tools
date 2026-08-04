# Example: create a monthly budget with email alerts for a GCP project.
# Replace locals with real values or remote state.
#
# Email notifications are delivered via a Cloud Functions gen2 function backed
# by Cloud Run v2.  If your organisation enforces the
# "cloudfunctions.requireVPCConnector" org policy you MUST supply vpc_connector;
# omit it (or set it to null) in environments that do not require a VPC connector.

locals {
  billing_account = "ABCDEF-123456-789012"
  project_id      = "my-workload-project"
}

module "budget" {
  source = "../../"

  billing_account      = local.billing_account
  project_id           = local.project_id
  project_name         = "my-workload"
  monthly_budget_limit = 500
  region               = "europe-west1"

  currency_code           = "USD"
  alert_threshold_percent = 0.8

  email_recipients = [
    "finance@example.com",
    "platform-team@example.com",
  ]

  # Uncomment and set when cloudfunctions.requireVPCConnector is enforced:
  # vpc_connector = "projects/my-workload-project/locations/europe-west1/connectors/my-connector"
}
