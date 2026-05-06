# Example: register iOS and Android apps in a Firebase project.
# Replace locals with real values from your mobile team.

locals {
  project_id = "my-firebase-project"
}

module "mobile_apps" {
  source = "../../"

  project_id = local.project_id
  region     = "us-central1"

  # iOS app (Apple)
  apple_display_name = "My App iOS"
  apple_bundle_id    = "com.example.myapp"
  apple_team_id      = "ABCDE12345"

  # Android app
  android_display_name  = "My App Android"
  android_package_name  = "com.example.myapp"
  android_sha1_hashes   = ["AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD"]
  android_sha256_hashes = ["aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"]
}

output "apple_app_id" {
  description = "Firebase app ID for the iOS app"
  value       = module.mobile_apps.apple_app_id
}

output "android_app_id" {
  description = "Firebase app ID for the Android app"
  value       = module.mobile_apps.android_app_id
}
