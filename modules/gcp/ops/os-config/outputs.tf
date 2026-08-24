output "patch_deployment_ids" {
  description = "Map of deployment key to the created patch deployment resource ID."
  value       = { for k, v in google_os_config_patch_deployment.this : k => v.id }
}

output "patch_deployment_names" {
  description = "Map of deployment key to the fully-qualified patch deployment name."
  value       = { for k, v in google_os_config_patch_deployment.this : k => v.name }
}
