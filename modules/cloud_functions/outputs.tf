output "function_name" {
  description = "Name of the Cloud Function"
  value       = google_cloudfunctions_function.function.name
}

output "function_uri" {
  description = "The URI of the Cloud Function"
  value       = google_cloudfunctions_function.function.https_trigger_url
}

output "function_service_account_email" {
  description = "The service account email used by the Cloud Function"
  value       = google_cloudfunctions_function.function.service_account_email
}

output "source_archive_bucket" {
  description = "The GCS bucket containing the function source code"
  value       = google_storage_bucket.functions_bucket.name
}

output "source_archive_object" {
  description = "The source archive object name"
  value       = google_storage_bucket_object.archive.name
}

output "function_id" {
  description = "An identifier for the resource with format projects/{{project}}/locations/{{region}}/functions/{{name}}"
  value       = google_cloudfunctions_function.function.id
}

output "function_self_link" {
  description = "The self link of the Cloud Function"
  value       = google_cloudfunctions_function.function.self_link
}

output "bucket_self_link" {
  description = "The self link of the function's source code bucket"
  value       = google_storage_bucket.functions_bucket.self_link
}