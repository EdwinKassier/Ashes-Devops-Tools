output "business_unit_folders" {
  description = "Map of business unit folder names to their folder IDs"
  value       = { for k, v in google_folder.business_units : k => v.name }
}

output "environment_folders" {
  description = "Map of environment folder names to their folder IDs"
  value       = { for k, v in google_folder.environments : k => v.name }
}

output "folder_ids" {
  description = "Map of all folder display names to their folder IDs"
  value = merge(
    { for k, v in google_folder.business_units : v.display_name => v.name },
    { for k, v in google_folder.environments : "${google_folder.business_units[split(".", k)[0]].display_name}/${v.display_name}" => v.name }
  )
} 