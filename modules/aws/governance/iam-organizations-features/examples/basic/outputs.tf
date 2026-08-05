output "enabled_features" {
  description = "The IAM organization features enabled by the module."
  value       = module.iam_organizations_features.enabled_features
}
