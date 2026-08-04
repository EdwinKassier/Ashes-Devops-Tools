output "apple_app_id" {
  description = "Firebase app ID for the iOS app"
  value       = module.mobile_apps.apple_app_id
}

output "android_app_id" {
  description = "Firebase app ID for the Android app"
  value       = module.mobile_apps.android_app_id
}
