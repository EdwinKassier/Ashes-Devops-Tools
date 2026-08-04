output "email" {
  description = "The email address of the service account"
  value       = google_service_account.service_account.email
}

output "name" {
  description = "The fully-qualified name of the service account"
  value       = google_service_account.service_account.name
}

output "unique_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.service_account.unique_id
}

output "member" {
  description = "The service account member string for use in IAM policies"
  value       = "serviceAccount:${google_service_account.service_account.email}"
}
