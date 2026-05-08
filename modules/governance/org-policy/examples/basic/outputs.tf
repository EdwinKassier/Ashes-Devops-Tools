output "enforced_policies" {
  description = "Boolean policies enforced by this module"
  value       = module.security_policies.enforced_boolean_policies
}
