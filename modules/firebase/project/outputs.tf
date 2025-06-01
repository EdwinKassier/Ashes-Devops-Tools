# Firebase Project Outputs
output "project_id" {
  description = "The Firebase project ID"
  value       = google_firebase_project.default.project
}

# Apple App Outputs
output "apple_app_id" {
  description = "The Apple app ID"
  value       = try(google_firebase_apple_app.default[0].app_id, "")
}

output "apple_api_key_id" {
  description = "The Apple API key ID"
  value       = try(google_apikeys_key.apple[0].uid, "")
}

# Android App Outputs
output "android_app_id" {
  description = "The Android app ID"
  value       = try(google_firebase_android_app.default[0].app_id, "")
}

# Web App Outputs
output "web_app_id" {
  description = "The Web app ID"
  value       = try(google_firebase_web_app.default[0].app_id, "")
}

output "firebase_config" {
  description = "The Firebase web config"
  value       = try(jsondecode(google_storage_bucket_object.firebase_config[0].content), {})
  sensitive   = true
}

output "firebase_config_bucket" {
  description = "The GCS bucket containing the Firebase config"
  value       = try(google_storage_bucket.firebase_web_config[0].name, "")
}
