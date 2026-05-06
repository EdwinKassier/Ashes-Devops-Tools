# Example: create a service account for a Cloud Run workload and grant
# it the minimum roles needed to read from GCS and write to BigQuery.

locals {
  project_id = "my-workload-project"
}

module "api_service_sa" {
  source = "../../"

  project_id   = local.project_id
  account_id   = "api-service"
  display_name = "API Service Account"
  description  = "Service account for the API Cloud Run service"

  project_roles = [
    "roles/bigquery.dataEditor",
    "roles/storage.objectViewer",
    "roles/cloudtrace.agent",
  ]
}

output "service_account_email" {
  description = "Email address of the created service account"
  value       = module.api_service_sa.email
}

output "service_account_member" {
  description = "IAM member string (e.g. serviceAccount:...@project.iam.gserviceaccount.com)"
  value       = module.api_service_sa.member
}
