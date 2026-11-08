output "patch_deployment_names" {
  description = "Deployment key to fully qualified patch deployment name."
  value       = module.os_config.patch_deployment_names
}
