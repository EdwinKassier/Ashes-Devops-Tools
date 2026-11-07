output "deny_policy_names" {
  description = "Deny policies created at the org node"
  value       = module.guardrails.deny_policy_names
}
