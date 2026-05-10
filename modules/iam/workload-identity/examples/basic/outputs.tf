output "workload_identity_provider" {
  description = "Full provider resource name for use in GitHub Actions 'workload_identity_provider' input"
  value       = module.github_wif.github_workload_identity_provider
}
