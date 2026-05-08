output "role_id" {
  description = "Full resource ID of the custom role — use this in IAM binding 'role' arguments"
  value       = module.cloud_run_deployer.role_id
}
